package com.example.poultech

import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import java.io.File
import java.io.FileOutputStream

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
                    try {
                        Log.d(TAG, "runModel called")
                        // Float32List from Dart can come as different types through method channel
                        // Get as Any first, then convert appropriately
                        val inputAny = call.argument<Any>("input")
                        if (inputAny == null) {
                            Log.e(TAG, "Input is null")
                            result.error("INVALID_ARGUMENT", "Input is null", null)
                            return@setMethodCallHandler
                        }
                        
                        // Convert to FloatArray based on actual type
                        val inputArray: FloatArray = when (inputAny) {
                            is FloatArray -> {
                                Log.d(TAG, "Input is FloatArray")
                                inputAny
                            }
                            is DoubleArray -> {
                                Log.d(TAG, "Input is DoubleArray, converting to FloatArray")
                                FloatArray(inputAny.size) { inputAny[it].toFloat() }
                            }
                            is List<*> -> {
                                Log.d(TAG, "Input is List, converting to FloatArray")
                                FloatArray(inputAny.size) { 
                                    when (val elem = inputAny[it]) {
                                        is Number -> elem.toFloat()
                                        is Double -> elem.toFloat()
                                        is Float -> elem
                                        else -> (elem as? Number)?.toFloat() ?: 0f
                                    }
                                }
                            }
                            is Array<*> -> {
                                Log.d(TAG, "Input is Array, converting to FloatArray")
                                FloatArray(inputAny.size) {
                                    when (val elem = inputAny[it]) {
                                        is Number -> elem.toFloat()
                                        is Double -> elem.toFloat()
                                        is Float -> elem
                                        else -> (elem as? Number)?.toFloat() ?: 0f
                                    }
                                }
                            }
                            else -> {
                                Log.e(TAG, "Unexpected input type: ${inputAny.javaClass.name}")
                                throw IllegalArgumentException("Unsupported input type: ${inputAny.javaClass.name}")
                            }
                        }
                        
                        Log.d(TAG, "Input size: ${inputArray.size}, expected: ${1 * 3 * 640 * 640}")
                        
                        // Ensure model is loaded
                        if (ortSession == null) {
                            Log.d(TAG, "Loading ONNX model...")
                            loadModel()
                            Log.d(TAG, "ONNX model loaded successfully")
                        }
                        
                        Log.d(TAG, "Running inference...")
                        val output = runInference(inputArray)
                        Log.d(TAG, "Inference completed, output size: ${output.size}")
                        result.success(output)
                    } catch (e: Exception) {
                        Log.e(TAG, "Error in runModel: ${e.message}", e)
                        result.error("INFERENCE_ERROR", e.message, null)
                    }
                }
                else -> {
                    Log.w(TAG, "Unknown method: ${call.method}")
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
        
        Log.d(TAG, "Input array size: ${inputArray.size}, expected: ${1 * 3 * 640 * 640}")
        
        // Create input tensor: shape [1, 3, 640, 640]
        val inputShape = longArrayOf(1, 3, 640, 640)
        
        // Create tensor - try FloatBuffer first (this method doesn't require allocator)
        val inputTensor = try {
            Log.d(TAG, "Creating tensor using FloatBuffer...")
            val floatBuffer = java.nio.FloatBuffer.wrap(inputArray)
            // Make it a direct buffer for better performance
            val directBuffer = java.nio.ByteBuffer.allocateDirect(inputArray.size * 4)
                .order(java.nio.ByteOrder.nativeOrder())
                .asFloatBuffer()
            directBuffer.put(inputArray)
            directBuffer.rewind()
            OnnxTensor.createTensor(ortEnvironment, directBuffer, inputShape)
        } catch (e: Exception) {
            Log.w(TAG, "FloatBuffer method failed: ${e.message}")
            // Fallback: try to get allocator and use the array method
            try {
                Log.d(TAG, "Trying with allocator from environment...")
                // Get allocator using reflection
                val allocatorField = OrtEnvironment::class.java.getDeclaredField("allocator")
                allocatorField.isAccessible = true
                val allocator = allocatorField.get(ortEnvironment)
                
                // Use reflection to call createTensor with allocator
                val createTensorMethod = OnnxTensor::class.java.getMethod(
                    "createTensor",
                    OrtEnvironment::class.java,
                    Class.forName("ai.onnxruntime.OrtAllocator"),
                    FloatArray::class.java,
                    LongArray::class.java
                )
                createTensorMethod.invoke(null, ortEnvironment, allocator, inputArray, inputShape) as OnnxTensor
            } catch (e2: Exception) {
                Log.e(TAG, "Allocator method also failed: ${e2.message}", e2)
                throw RuntimeException("Failed to create tensor. All methods failed. Last error: ${e2.message}", e2)
            }
        }
        
        var outputs: OrtSession.Result? = null
        try {
            // Try with "images" first (common YOLOv8 input name)
            var inputName = "images"
            try {
                val inputMap = HashMap<String, OnnxTensor>()
                inputMap["images"] = inputTensor
                outputs = session.run(inputMap)
                Log.d(TAG, "Using input name: images")
            } catch (e: Exception) {
                // If "images" doesn't work, the model might use a different input name
                // We'll need to handle this case - for now, rethrow to see the actual error
                Log.e(TAG, "Failed to run with 'images' input name: ${e.message}")
                throw e
            }
            
            // Get the output - OrtSession.Result has a get() method to access outputs
            // Try common output names first, then get the first available output
            val outputTensor = try {
                var tensor: OnnxTensor? = null
                
                // Try common YOLOv8 output names
                val outputNames = listOf("output0", "output", "output_0")
                for (outputName in outputNames) {
                    try {
                        val ortValue = outputs.get(outputName)
                        if (ortValue != null) {
                            // Try to get the value from OrtValue using reflection
                            // OrtValue might have getValue() method or value property
                            tensor = try {
                                // Try direct cast first
                                ortValue as? OnnxTensor
                            } catch (e: Exception) {
                                // Try getValue() method
                                try {
                                    val getValueMethod = ortValue.javaClass.getMethod("getValue")
                                    getValueMethod.invoke(ortValue) as? OnnxTensor
                                } catch (e2: Exception) {
                                    // Try value property/field
                                    try {
                                        val valueField = ortValue.javaClass.getDeclaredField("value")
                                        valueField.isAccessible = true
                                        valueField.get(ortValue) as? OnnxTensor
                                    } catch (e3: Exception) {
                                        null
                                    }
                                }
                            }
                            if (tensor != null) {
                                Log.d(TAG, "Found output with name: $outputName")
                                break
                            }
                        }
                    } catch (e: Exception) {
                        Log.d(TAG, "Output name '$outputName' not found: ${e.message}")
                        // Continue to next name
                    }
                }
                
                // If not found by name, get the first output using outputNames from session
                if (tensor == null) {
                    try {
                        // Get output names from session using reflection
                        val outputNamesMethod = session.javaClass.getMethod("outputNames")
                        val sessionOutputNames = outputNamesMethod.invoke(session) as? List<*>
                        if (sessionOutputNames != null && sessionOutputNames.isNotEmpty()) {
                            val firstOutputName = sessionOutputNames[0] as String
                            Log.d(TAG, "Using first output name from session: $firstOutputName")
                            val ortValue = outputs.get(firstOutputName)
                            if (ortValue != null) {
                                tensor = try {
                                    ortValue as? OnnxTensor
                                } catch (e: Exception) {
                                    try {
                                        val getValueMethod = ortValue.javaClass.getMethod("getValue")
                                        getValueMethod.invoke(ortValue) as? OnnxTensor
                                    } catch (e2: Exception) {
                                        try {
                                            val valueField = ortValue.javaClass.getDeclaredField("value")
                                            valueField.isAccessible = true
                                            valueField.get(ortValue) as? OnnxTensor
                                        } catch (e3: Exception) {
                                            null
                                        }
                                    }
                                }
                            }
                        }
                    } catch (e: Exception) {
                        Log.w(TAG, "Failed to get output by name: ${e.message}")
                    }
                }
                
                // Last resort: try to get output by index (if Result supports it)
                if (tensor == null) {
                    try {
                        // Some versions might support get(index)
                        val getMethod = outputs.javaClass.getMethod("get", Int::class.java)
                        val ortValue = getMethod.invoke(outputs, 0)
                        if (ortValue != null) {
                            tensor = try {
                                ortValue as? OnnxTensor
                            } catch (e: Exception) {
                                try {
                                    val getValueMethod = ortValue.javaClass.getMethod("getValue")
                                    getValueMethod.invoke(ortValue) as? OnnxTensor
                                } catch (e2: Exception) {
                                    try {
                                        val valueField = ortValue.javaClass.getDeclaredField("value")
                                        valueField.isAccessible = true
                                        valueField.get(ortValue) as? OnnxTensor
                                    } catch (e3: Exception) {
                                        null
                                    }
                                }
                            }
                            if (tensor != null) {
                                Log.d(TAG, "Got output by index 0")
                            }
                        }
                    } catch (e: Exception) {
                        Log.w(TAG, "Failed to get output by index: ${e.message}")
                    }
                }
                
                tensor ?: throw IllegalStateException("Could not find output tensor in result")
            } catch (e: Exception) {
                throw RuntimeException("Could not access output: ${e.message}", e)
            }
            
            val outputBuffer = outputTensor.floatBuffer
            
            // Get the actual shape from the tensor to calculate total size
            val totalSize = try {
                val tensorInfo = outputTensor.info
                val outputShape = tensorInfo.shape
                val calculatedSize = outputShape.fold(1L) { acc: Long, dim: Long -> acc * dim }.toInt()
                Log.d(TAG, "Output shape: ${outputShape.joinToString()}, calculated size: $calculatedSize")
                calculatedSize
            } catch (e: Exception) {
                Log.w(TAG, "Failed to get shape from tensor info: ${e.message}, using expected size")
                // Fallback to expected post-NMS output size (1, 300, 6)
                1 * 300 * 6
            }
            
            Log.d(TAG, "Total size: $totalSize, buffer capacity: ${outputBuffer.capacity()}, remaining: ${outputBuffer.remaining()}")
            
            // Ensure buffer is at the start
            outputBuffer.rewind()
            
            // Read the correct number of values based on shape
            // If buffer capacity is smaller, that's a problem
            if (outputBuffer.capacity() < totalSize) {
                Log.e(TAG, "Buffer capacity (${outputBuffer.capacity()}) is smaller than expected size ($totalSize)")
                throw RuntimeException("Output buffer too small. Capacity: ${outputBuffer.capacity()}, Expected: $totalSize")
            }
            
            val outputArray = FloatArray(totalSize)
            outputBuffer.get(outputArray)
            
            Log.d(TAG, "Successfully read ${outputArray.size} values from output tensor")
            
            // Convert to List<Float>
            return outputArray.toList()
        } catch (e: Exception) {
            Log.e(TAG, "Error during inference: ${e.message}", e)
            throw RuntimeException("Failed to run inference: ${e.message}", e)
        } finally {
            inputTensor.close()
            // Close all output tensors in the result
            outputs?.let { result ->
                try {
                    // Try to close the result itself if it's AutoCloseable
                    if (result is AutoCloseable) {
                        result.close()
                    } else {
                        // Otherwise try to close individual values
                        @Suppress("UNCHECKED_CAST")
                        val resultMap = result as? Map<String, Any>
                        resultMap?.values?.forEach { value ->
                            if (value is AutoCloseable) {
                                try {
                                    value.close()
                                } catch (e: Exception) {
                                    // Ignore close errors
                                }
                            }
                        }
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "Error closing outputs: ${e.message}")
                }
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        ortSession?.close()
        // Note: OrtEnvironment is a singleton, don't close it here
    }
}
