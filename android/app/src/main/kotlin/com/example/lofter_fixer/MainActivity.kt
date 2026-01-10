package com.example.lofter_fixer

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaScannerConnection
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
    private val INPUT_SIZE = 640 

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        OpenCVLoader.initDebug()

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "processImages") {
                val tasks = call.argument<List<Map<String, String>>>("tasks") ?: listOf()
                val confThreshold = call.argument<Double>("confidence")?.toFloat() ?: 0.5f
                
                CoroutineScope(Dispatchers.IO).launch {
                    try {
                        if (tflite == null) {
                            val modelFile = FileUtil.loadMappedFile(context, "best_float16.tflite")
                            tflite = Interpreter(modelFile)
                        }
                        
                        var successCount = 0
                        val debugLogs = StringBuilder()

                        tasks.forEach { task ->
                            val wmPath = task["wm"]!!
                            val cleanPath = task["clean"]!!
                            val log = processOneImage(wmPath, cleanPath, confThreshold)
                            if (log == "SUCCESS") {
                                successCount++
                            } else {
                                debugLogs.append("${File(wmPath).name} -> $log\n")
                            }
                        }
                        
                        withContext(Dispatchers.Main) {
                            if (successCount == 0 && tasks.isNotEmpty()) {
                                result.error("NO_DETECTION", "未检测到水印:\n$debugLogs", null)
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
            val wmBitmap = BitmapFactory.decodeFile(wmPath) ?: return "无法读取"
            val cleanBitmap = BitmapFactory.decodeFile(cleanPath) ?: return "无法读取原图"

            // 图像预处理 (保持不变，这是识别准确的关键)
            val imageProcessor = ImageProcessor.Builder()
                .add(ResizeOp(INPUT_SIZE, INPUT_SIZE, ResizeOp.ResizeMethod.BILINEAR))
                .add(NormalizeOp(0f, 255f)) 
                .build()
            var tImage = TensorImage.fromBitmap(wmBitmap)
            tImage = imageProcessor.process(tImage)

            val outputTensor = tflite!!.getOutputTensor(0)
            val outputShape = outputTensor.shape() 
            val dim1 = outputShape[1]
            val dim2 = outputShape[2]
            val outputArray = Array(1) { Array(dim1) { FloatArray(dim2) } }
            
            tflite!!.run(tImage.buffer, outputArray)

            val bestBox = if (dim1 > dim2) {
                 parseOutputTransposed(outputArray[0], confThreshold, wmBitmap.width, wmBitmap.height)
            } else {
                 parseOutputStandard(outputArray[0], confThreshold, wmBitmap.width, wmBitmap.height)
            }

            return if (bestBox != null) {
                repairWithOpenCV(wmBitmap, cleanBitmap, bestBox, wmPath)
                "SUCCESS"
            } else {
                "置信度过低"
            }
        } catch (e: Exception) {
            return "异常: ${e.message}"
        }
    }

    // ... (parseOutputStandard 和 parseOutputTransposed 保持之前的逻辑不变) ...
    // 为节省篇幅，这里假设你保留了之前的 parse 逻辑，只展示保存部分的修改
    // 请务必把之前的 parseOutputStandard, parseOutputTransposed, convertToRect, repairWithOpenCV 完整保留！
    // 👇 我在这里为了完整性，还是贴一下 repairWithOpenCV 和 saveBitmap 的修改版

    private fun parseOutputStandard(rows: Array<FloatArray>, confThresh: Float, imgW: Int, imgH: Int): Rect? {
        val numAnchors = rows[0].size 
        var maxConf = 0f
        var bestIdx = -1
        for (i in 0 until numAnchors) {
            val conf = rows[4][i] 
            if (conf > maxConf) { maxConf = conf; bestIdx = i }
        }
        if (maxConf < confThresh) return null
        return convertToRect(rows[0][bestIdx], rows[1][bestIdx], rows[2][bestIdx], rows[3][bestIdx], imgW, imgH)
    }

    private fun parseOutputTransposed(rows: Array<FloatArray>, confThresh: Float, imgW: Int, imgH: Int): Rect? {
        var maxConf = 0f
        var bestIdx = -1
        for (i in rows.indices) {
            val conf = rows[i][4] 
            if (conf > maxConf) { maxConf = conf; bestIdx = i }
        }
        if (maxConf < confThresh) return null
        return convertToRect(rows[bestIdx][0], rows[bestIdx][1], rows[bestIdx][2], rows[bestIdx][3], imgW, imgH)
    }

    private fun convertToRect(cx: Float, cy: Float, w: Float, h: Float, imgW: Int, imgH: Int): Rect {
        val scaleX = imgW.toFloat() / INPUT_SIZE
        val scaleY = imgH.toFloat() / INPUT_SIZE
        val finalX = ((cx - w / 2) * scaleX).toInt()
        val finalY = ((cy - h / 2) * scaleY).toInt()
        val finalW = (w * scaleX).toInt()
        val finalH = (h * scaleY).toInt()
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
        val wmMat = Mat(); val cleanMat = Mat()
        Utils.bitmapToMat(wmBm, wmMat); Utils.bitmapToMat(cleanBm, cleanMat)
        Imgproc.resize(cleanMat, cleanMat, wmMat.size(), 0.0, 0.0, Imgproc.INTER_LANCZOS4)
        
        val safeRect = Rect(
            rect.x.coerceIn(0, wmMat.cols()), rect.y.coerceIn(0, wmMat.rows()),
            rect.width.coerceAtMost(wmMat.cols() - rect.x), rect.height.coerceAtMost(wmMat.rows() - rect.y)
        )

        if (safeRect.width > 0 && safeRect.height > 0) {
            val patch = cleanMat.submat(safeRect)
            patch.copyTo(wmMat.submat(safeRect))
            val resultBm = Bitmap.createBitmap(wmMat.cols(), wmMat.rows(), Bitmap.Config.ARGB_8888)
            Utils.matToBitmap(wmMat, resultBm)
            saveBitmap(resultBm, originalPath)
        }
    }

    // 👇👇👇 核心修改：保存到 Download 并广播 👇👇👇
    private fun saveBitmap(bm: Bitmap, originalPath: String) {
        val originalFile = File(originalPath)
        // 改为 Download 目录，方便查找
        val dir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS), "LofterFixed")
        if (!dir.exists()) dir.mkdirs()
        
        val file = File(dir, "Fixed_${originalFile.name}")
        FileOutputStream(file).use { out ->
            bm.compress(Bitmap.CompressFormat.JPEG, 98, out)
        }

        // ✨ 魔法步骤：告诉系统相册“这里有个新图片”，让它立马显形
        MediaScannerConnection.scanFile(context, arrayOf(file.toString()), arrayOf("image/jpeg"), null)
    }
}