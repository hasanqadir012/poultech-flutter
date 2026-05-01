package com.example.poultech

import androidx.annotation.Keep
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import java.io.File
import java.io.FileOutputStream
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.media.ExifInterface
import android.graphics.Matrix

@Keep
class MainActivity : FlutterActivity() {
    private val CHANNEL = "poultech/onnx"
    private val TAG = "PoultechONNX"
    private var ortSession: OrtSession? = null
    private val ortEnvironment = OrtEnvironment.getEnvironment()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "runModel" -> {
                    Thread {
                        try {
                            Log.d(TAG, "runModel called")
                            val imagePath = call.argument<String>("imagePath")
                            val inputAny = call.argument<Any>("input")
                            
                            val inputArray: FloatArray
                            var imgInfo: Map<String, Any>? = null
                            
                            if (imagePath != null) {
                                Log.d(TAG, "Native preprocessing image: $imagePath")
                                val preprocessed = preprocessImageNative(imagePath)
                                inputArray = preprocessed.first
                                imgInfo = preprocessed.second
                            } else if (inputAny != null) {
                                inputArray = when (inputAny) {
                                    is FloatArray -> inputAny
                                    is DoubleArray -> FloatArray(inputAny.size) { inputAny[it].toFloat() }
                                    is List<*> -> FloatArray(inputAny.size) { 
                                        when (val elem = inputAny[it]) {
                                            is Number -> elem.toFloat()
                                            else -> 0f
                                        }
                                    }
                                    is Array<*> -> FloatArray(inputAny.size) {
                                        when (val elem = inputAny[it]) {
                                            is Number -> elem.toFloat()
                                            else -> 0f
                                        }
                                    }
                                    else -> throw IllegalArgumentException("Unsupported input")
                                }
                            } else {
                                runOnUiThread {
                                    Log.e(TAG, "Input is null")
                                    result.error("INVALID_ARGUMENT", "Input is null", null)
                                }
                                return@Thread
                            }
                            
                            if (ortSession == null) {
                                Log.d(TAG, "Loading ONNX model...")
                                loadModel()
                            }
                            
                            val output = runInference(inputArray)
                            
                            if (imgInfo != null) {
                                val resultMap = HashMap<String, Any>()
                                resultMap["output"] = output
                                resultMap.putAll(imgInfo)
                                runOnUiThread { result.success(resultMap) }
                            } else {
                                runOnUiThread { result.success(output) }
                            }
                        } catch (e: Throwable) {
                            runOnUiThread {
                                Log.e(TAG, "Error in runModel: ${e.message}", e)
                                result.error("INFERENCE_ERROR", e.message, null)
                            }
                        }
                    }.start()
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun loadModel() {
        try {
            // Copy model from Flutter assets to a temp file
            // Flutter assets are in "flutter_assets/" directory
            val modelFile = File(cacheDir, "best.onnx")
            Log.d(TAG, "Model file path: ${modelFile.absolutePath}")
            
            if (!modelFile.exists()) {
                Log.d(TAG, "Model file doesn't exist, copying from assets...")
                var copied = false
                
                // Try different possible paths for Flutter assets
                val possiblePaths = listOf(
                    "flutter_assets/assets/best.onnx",
                    "assets/best.onnx",
                    "best.onnx"
                )
                
                for (assetPath in possiblePaths) {
                    try {
                        Log.d(TAG, "Trying asset path: $assetPath")
                        assets.open(assetPath).use { input ->
                            FileOutputStream(modelFile).use { output ->
                                input.copyTo(output)
                            }
                        }
                        Log.d(TAG, "Successfully copied model from: $assetPath")
                        copied = true
                        break
                    } catch (e: Exception) {
                        Log.d(TAG, "Failed to load from $assetPath: ${e.message}")
                        // Continue to next path
                    }
                }
                
                if (!copied) {
                    throw RuntimeException("Model file not found in any asset path. Tried: ${possiblePaths.joinToString()}")
                }
            } else {
                Log.d(TAG, "Model file already exists, using cached version")
            }
            
            Log.d(TAG, "Creating ONNX session...")
            val sessionOptions = OrtSession.SessionOptions()
            ortSession = ortEnvironment.createSession(modelFile.absolutePath, sessionOptions)
            Log.d(TAG, "ONNX session created successfully")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to load ONNX model: ${e.message}", e)
            throw RuntimeException("Failed to load ONNX model: ${e.message}", e)
        }
    }

    private fun runInference(inputArray: FloatArray): List<Float> {
        val session = ortSession ?: throw IllegalStateException("Model not loaded")
        val inputShape = longArrayOf(1, 3, 640, 640)
        
        // Anchor the ByteBuffer so GC doesn't kill it during inference!
        val byteBuffer = java.nio.ByteBuffer.allocateDirect(inputArray.size * 4)
            .order(java.nio.ByteOrder.nativeOrder())
        val directBuffer = byteBuffer.asFloatBuffer()
        directBuffer.put(inputArray)
        directBuffer.rewind()
        
        val inputTensor = try {
            OnnxTensor.createTensor(ortEnvironment, directBuffer, inputShape)
        } catch (e: Exception) {
            throw RuntimeException("Failed to create input tensor: ${e.message}", e)
        }
        
        var outputs: OrtSession.Result? = null
        try {
            val inputMap = HashMap<String, OnnxTensor>()
            inputMap["images"] = inputTensor
            outputs = session.run(inputMap)
            
            // Safely get output without reflection
            val iterator = outputs.iterator()
            if (!iterator.hasNext()) {
                 throw IllegalStateException("Model returned empty result")
            }
            val entry = iterator.next()
            val outputTensor = entry.value as? OnnxTensor ?: throw IllegalStateException("Expected OnnxTensor but got ${entry.value?.javaClass?.name}")
            
            val outputBuffer = outputTensor.floatBuffer
            
            val tensorInfo = outputTensor.info
            val calculatedSize = tensorInfo.shape.fold(1L) { acc, dim -> acc * dim }.toInt()
            
            outputBuffer.rewind()
            val outputArray = FloatArray(calculatedSize)
            outputBuffer.get(outputArray)
            
            // This log forces the compiler/GC to keep byteBuffer alive until here!
            Log.d(TAG, "Inference completed. Buffer anchored: ${byteBuffer.capacity()}")
            
            return outputArray.toList()
        } catch (e: Exception) {
            throw RuntimeException("Failed to run inference: ${e.message}", e)
        } finally {
            inputTensor.close()
            outputs?.close()
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        ortSession?.close()
        // Note: OrtEnvironment is a singleton, don't close it here
    }

    private fun preprocessImageNative(imagePath: String): Pair<FloatArray, Map<String, Any>> {
        val options = BitmapFactory.Options()
        options.inJustDecodeBounds = true
        BitmapFactory.decodeFile(imagePath, options)
        
        val exif = try { ExifInterface(imagePath) } catch (e: Exception) { null }
        val orientation = exif?.getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL) ?: ExifInterface.ORIENTATION_NORMAL
        
        var scale = 1
        while (options.outWidth / scale / 2 >= 640 && options.outHeight / scale / 2 >= 640) {
            scale *= 2
        }
        options.inJustDecodeBounds = false
        options.inSampleSize = scale
        
        var srcBitmap = BitmapFactory.decodeFile(imagePath, options)
            ?: throw IllegalArgumentException("Could not decode image at $imagePath")
            
        // Handle rotation naturally
        val matrix = Matrix()
        when (orientation) {
            ExifInterface.ORIENTATION_ROTATE_90 -> matrix.postRotate(90f)
            ExifInterface.ORIENTATION_ROTATE_180 -> matrix.postRotate(180f)
            ExifInterface.ORIENTATION_ROTATE_270 -> matrix.postRotate(270f)
        }
        if (orientation == ExifInterface.ORIENTATION_ROTATE_90 || orientation == ExifInterface.ORIENTATION_ROTATE_180 || orientation == ExifInterface.ORIENTATION_ROTATE_270) {
            val rotated = Bitmap.createBitmap(srcBitmap, 0, 0, srcBitmap.width, srcBitmap.height, matrix, true)
            if (rotated != srcBitmap) {
                srcBitmap.recycle()
                srcBitmap = rotated
            }
        }
        
        val originalWidth = srcBitmap.width
        val originalHeight = srcBitmap.height
        
        val r = Math.min(640.0 / originalWidth, 640.0 / originalHeight)
        val resizedW = (originalWidth * r).toInt()
        val resizedH = (originalHeight * r).toInt()
        
        val padLeft = (640 - resizedW) / 2
        val padTop = (640 - resizedH) / 2
        
        val scaledBitmap = Bitmap.createScaledBitmap(srcBitmap, resizedW, resizedH, true)
        
        val canvasBitmap = Bitmap.createBitmap(640, 640, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(canvasBitmap)
        canvas.drawColor(android.graphics.Color.rgb(114, 114, 114))
        canvas.drawBitmap(scaledBitmap, padLeft.toFloat(), padTop.toFloat(), null)
        
        val pixels = IntArray(640 * 640)
        canvasBitmap.getPixels(pixels, 0, 640, 0, 0, 640, 640)
        
        val floatArray = FloatArray(3 * 640 * 640)
        for (y in 0 until 640) {
            for (x in 0 until 640) {
                val pixel = pixels[y * 640 + x]
                val rVal = ((pixel shr 16) and 0xFF) / 255.0f
                val gVal = ((pixel shr 8) and 0xFF) / 255.0f
                val bVal = (pixel and 0xFF) / 255.0f
                
                floatArray[0 * 640 * 640 + y * 640 + x] = rVal
                floatArray[1 * 640 * 640 + y * 640 + x] = gVal
                floatArray[2 * 640 * 640 + y * 640 + x] = bVal
            }
        }
        
        srcBitmap.recycle()
        if (scaledBitmap != srcBitmap) scaledBitmap.recycle()
        canvasBitmap.recycle()
        
        val info = mapOf<String, Any>(
            "imgWidth" to originalWidth,
            "imgHeight" to originalHeight,
            "ratio" to r,
            "padW" to padLeft.toDouble(),
            "padH" to padTop.toDouble()
        )
        
        return Pair(floatArray, info)
    }
}
