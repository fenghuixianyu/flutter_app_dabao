package com.example.lofter_fixer

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Environment
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.opencv.android.OpenCVLoader
import org.opencv.android.Utils
import org.opencv.core.Mat
import org.opencv.core.Rect
import org.opencv.imgproc.Imgproc
import org.tensorflow.lite.Interpreter
import org.tensorflow.lite.support.common.FileUtil
import org.tensorflow.lite.support.common.ops.NormalizeOp
import org.tensorflow.lite.support.image.ImageProcessor
import org.tensorflow.lite.support.image.TensorImage
import org.tensorflow.lite.support.image.ops.ResizeOp
import java.io.File
import java.io.FileOutputStream
import java.util.Collections

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.lofter_fixer/processor"
    private var tflite: Interpreter? = null
    
    // YOLOv8 默认输入尺寸
    private val INPUT_SIZE = 640 

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        if (!OpenCVLoader.initDebug()) {
            println("❌ OpenCV Load Failed!")
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "processImages") {
                val tasks = call.argument<List<Map<String, String>>>("tasks") ?: listOf()
                val confThreshold = call.argument<Double>("confidence")?.toFloat() ?: 0.5f
                
                CoroutineScope(Dispatchers.IO).launch {
                    try {
                        // 1. 加载模型
                        if (tflite == null) {
                            val modelFile = FileUtil.loadMappedFile(context, "best_float16.tflite")
                            tflite = Interpreter(modelFile)
                        }
                        
                        var successCount = 0
                        // 记录调试信息以便排查
                        val debugLogs = StringBuilder()

                        tasks.forEach { task ->
                            val wmPath = task["wm"]!!
                            val cleanPath = task["clean"]!!
                            val log = processOneImage(wmPath, cleanPath, confThreshold)
                            if (log == "SUCCESS") {
                                successCount++
                            } else {
                                debugLogs.append("File: ${File(wmPath).name} -> $log\n")
                            }
                        }
                        
                        withContext(Dispatchers.Main) {
                            if (successCount == 0 && tasks.isNotEmpty()) {
                                // 如果全是0，把错误日志返给 Flutter 显示
                                result.error("NO_DETECTION", "未检测到水印，调试信息：\n$debugLogs", null)
                            } else {
                                result.success(successCount)
                            }
                        }
                    } catch (e: Exception) {
                        withContext(Dispatchers.Main) {
                            result.error("ERR", "系统错误: ${e.message}", null)
                        }
                    }
                }
            } else {
                result.notImplemented()
            }
        }
    }

    private fun processOneImage(wmPath: String, cleanPath: String, confThreshold: Float): String {
        try {
            val wmBitmap = BitmapFactory.decodeFile(wmPath) ?: return "无法读取图片"
            val cleanBitmap = BitmapFactory.decodeFile(cleanPath) ?: return "无法读取原图"

            // --- 核心修复点 1: 图像预处理 ---
            // Float 模型必须把 0-255 归一化到 0.0-1.0
            val imageProcessor = ImageProcessor.Builder()
                .add(ResizeOp(INPUT_SIZE, INPUT_SIZE, ResizeOp.ResizeMethod.BILINEAR))
                .add(NormalizeOp(0f, 255f)) // ⚠️ 这一步至关重要！
                .build()
                
            var tImage = TensorImage.fromBitmap(wmBitmap)
            tImage = imageProcessor.process(tImage)

            // --- 核心修复点 2: 动态形状适配 ---
            val outputTensor = tflite!!.getOutputTensor(0)
            val outputShape = outputTensor.shape() // 例如 [1, 5, 8400]
            val outputBuffer = outputTensor.dataType()
            
            // 准备输出容器
            // outputShape 可能是 [1, 5, 8400] 或是 [1, 8400, 5]
            val dim1 = outputShape[1]
            val dim2 = outputShape[2]
            val outputArray = Array(1) { Array(dim1) { FloatArray(dim2) } }
            
            tflite!!.run(tImage.buffer, outputArray)

            // 解析输出 (找出置信度最高的框)
            // 需要判断是哪种排列方式
            val bestBox = if (dim1 > dim2) {
                 // [1, 8400, 5] 格式 (Transpose过)
                 parseOutputTransposed(outputArray[0], confThreshold, wmBitmap.width, wmBitmap.height)
            } else {
                 // [1, 5, 8400] 格式 (默认)
                 parseOutputStandard(outputArray[0], confThreshold, wmBitmap.width, wmBitmap.height)
            }

            return if (bestBox != null) {
                repairWithOpenCV(wmBitmap, cleanBitmap, bestBox, wmPath)
                "SUCCESS"
            } else {
                "置信度过低 (最高未能达到 $confThreshold)"
            }

        } catch (e: Exception) {
            return "处理异常: ${e.message}"
        }
    }

    // 处理 [5, 8400] 格式
    private fun parseOutputStandard(rows: Array<FloatArray>, confThresh: Float, imgW: Int, imgH: Int): Rect? {
        val numAnchors = rows[0].size // 8400
        var maxConf = 0f
        var bestIdx = -1

        for (i in 0 until numAnchors) {
            val conf = rows[4][i] // index 4 是置信度
            if (conf > maxConf) {
                maxConf = conf
                bestIdx = i
            }
        }

        // 如果连 0.1 都没达到，也记录一下最大值方便调试
        if (maxConf < confThresh) return null

        val cx = rows[0][bestIdx]
        val cy = rows[1][bestIdx]
        val w = rows[2][bestIdx]
        val h = rows[3][bestIdx]
        
        return convertToRect(cx, cy, w, h, imgW, imgH)
    }

    // 处理 [8400, 5] 格式
    private fun parseOutputTransposed(rows: Array<FloatArray>, confThresh: Float, imgW: Int, imgH: Int): Rect? {
        var maxConf = 0f
        var bestIdx = -1

        for (i in rows.indices) {
            val conf = rows[i][4] 
            if (conf > maxConf) {
                maxConf = conf
                bestIdx = i
            }
        }

        if (maxConf < confThresh) return null

        val cx = rows[bestIdx][0]
        val cy = rows[bestIdx][1]
        val w = rows[bestIdx][2]
        val h = rows[bestIdx][3]
        
        return convertToRect(cx, cy, w, h, imgW, imgH)
    }

    private fun convertToRect(cx: Float, cy: Float, w: Float, h: Float, imgW: Int, imgH: Int): Rect {
        val scaleX = imgW.toFloat() / INPUT_SIZE
        val scaleY = imgH.toFloat() / INPUT_SIZE
        
        val finalX = ((cx - w / 2) * scaleX).toInt()
        val finalY = ((cy - h / 2) * scaleY).toInt()
        val finalW = (w * scaleX).toInt()
        val finalH = (h * scaleY).toInt()

        // 稍微扩大范围 (Padding)
        val paddingW = (finalW * 0.2).toInt()
        val paddingH = (finalH * 0.1).toInt()

        return Rect(
            (finalX - paddingW).coerceAtLeast(0),
            (finalY - paddingH).coerceAtLeast(0),
            (finalW + paddingW * 2).coerceAtMost(imgW),
            (finalH + paddingH * 2).coerceAtMost(imgH)
        )
    }

    private fun repairWithOpenCV(wmBm: Bitmap, cleanBm: Bitmap, rect: Rect, originalPath: String) {
        val wmMat = Mat()
        val cleanMat = Mat()
        Utils.bitmapToMat(wmBm, wmMat)
        Utils.bitmapToMat(cleanBm, cleanMat)

        Imgproc.resize(cleanMat, cleanMat, wmMat.size(), 0.0, 0.0, Imgproc.INTER_LANCZOS4)
        
        // 安全检查，防止 rect 越界导致 crash
        val safeRect = Rect(
            rect.x.coerceIn(0, wmMat.cols()),
            rect.y.coerceIn(0, wmMat.rows()),
            rect.width.coerceAtMost(wmMat.cols() - rect.x),
            rect.height.coerceAtMost(wmMat.rows() - rect.y)
        )

        if (safeRect.width > 0 && safeRect.height > 0) {
            val patch = cleanMat.submat(safeRect)
            patch.copyTo(wmMat.submat(safeRect))
            
            val resultBm = Bitmap.createBitmap(wmMat.cols(), wmMat.rows(), Bitmap.Config.ARGB_8888)
            Utils.matToBitmap(wmMat, resultBm)
            saveBitmap(resultBm, originalPath)
        }
    }

    private fun saveBitmap(bm: Bitmap, originalPath: String) {
        val originalFile = File(originalPath)
        val dir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES), "LofterFixed")
        if (!dir.exists()) dir.mkdirs()
        
        val file = File(dir, "Fixed_${originalFile.name}")
        FileOutputStream(file).use { out ->
            bm.compress(Bitmap.CompressFormat.JPEG, 98, out)
        }
    }
}