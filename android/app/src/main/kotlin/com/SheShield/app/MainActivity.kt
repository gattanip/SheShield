package com.SheShield.app

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.util.Log
import android.widget.Toast
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.SheShield.app/emergency"
    private val SMS_PERMISSION_REQUEST = 1001
    private val TAG = "SheShieldMainActivity"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestSMSPermissions" -> {
                    Log.d(TAG, "Requesting SMS permissions")
                    requestSMSPermissions(result)
                }
                "sendEmergencyMessage" -> {
                    val phoneNumber = call.argument<String>("phoneNumber")
                    val message = call.argument<String>("message")
                    val currentLocation = call.argument<String>("currentLocation")
                    val trackingUrl = call.argument<String>("trackingUrl")
                    
                    Log.d(TAG, "Preparing emergency message for: $phoneNumber")
                    
                    if (phoneNumber == null || message == null) {
                        Log.e(TAG, "Invalid arguments: phoneNumber or message is null")
                        result.error("INVALID_ARGUMENTS", "Phone number and message are required", null)
                        return@setMethodCallHandler
                    }

                    // Format the complete message with location information
                    val completeMessage = buildString {
                        append(message)
                        if (currentLocation != null) {
                            append("\n\nCurrent Location: ")
                            append(currentLocation)
                        }
                        if (trackingUrl != null) {
                            append("\n\nLive Tracking: ")
                            append(trackingUrl)
                        }
                    }

                    // Try WhatsApp first
                    trySendWhatsApp(phoneNumber, completeMessage, result)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun trySendWhatsApp(phoneNumber: String, message: String, result: MethodChannel.Result) {
        // Format phone number (remove spaces, ensure it starts with country code)
        val formattedNumber = phoneNumber.trim().replace(" ", "")
        
        try {
            // Try WhatsApp app first
            Log.d(TAG, "Opening WhatsApp")
            val intent = Intent(Intent.ACTION_VIEW).apply {
                data = Uri.parse("whatsapp://send?phone=$formattedNumber&text=${Uri.encode(message)}")
                setPackage("com.whatsapp")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            Toast.makeText(this, "Opening WhatsApp...", Toast.LENGTH_SHORT).show()
            result.success(true)
        } catch (e: Exception) {
            Log.d(TAG, "WhatsApp app not found, trying WhatsApp Business", e)
            try {
                // Try WhatsApp Business
                val intent = Intent(Intent.ACTION_VIEW).apply {
                    data = Uri.parse("whatsapp://send?phone=$formattedNumber&text=${Uri.encode(message)}")
                    setPackage("com.whatsapp.w4b")
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                startActivity(intent)
                Toast.makeText(this, "Opening WhatsApp Business...", Toast.LENGTH_SHORT).show()
                result.success(true)
            } catch (e2: Exception) {
                Log.d(TAG, "WhatsApp Business not found, trying web WhatsApp", e2)
                try {
                    // Last resort: try web WhatsApp
                    val webIntent = Intent(Intent.ACTION_VIEW).apply {
                        data = Uri.parse("https://api.whatsapp.com/send?phone=$formattedNumber&text=${Uri.encode(message)}")
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    startActivity(webIntent)
                    Toast.makeText(this, "Opening WhatsApp Web...", Toast.LENGTH_SHORT).show()
                    result.success(true)
                } catch (e3: Exception) {
                    Log.e(TAG, "All WhatsApp methods failed, falling back to SMS", e3)
                    // Fall back to SMS
                    trySendSMS(phoneNumber, message, result)
                }
            }
        }
    }

    private fun trySendSMS(phoneNumber: String, message: String, result: MethodChannel.Result) {
        try {
            // Open SMS app with pre-filled message
            val intent = Intent(Intent.ACTION_SENDTO).apply {
                data = Uri.parse("smsto:$phoneNumber")
                putExtra("sms_body", message)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            Toast.makeText(this, "Opening SMS app...", Toast.LENGTH_SHORT).show()
            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to open SMS app", e)
            result.error("MESSAGE_ERROR", "Could not open messaging apps: ${e.message}", null)
        }
    }

    private fun checkSMSPermissions(): Boolean {
        val hasPermissions = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ContextCompat.checkSelfPermission(this, Manifest.permission.SEND_SMS) == PackageManager.PERMISSION_GRANTED &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.READ_SMS) == PackageManager.PERMISSION_GRANTED &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.RECEIVE_SMS) == PackageManager.PERMISSION_GRANTED
        } else {
            ContextCompat.checkSelfPermission(this, Manifest.permission.SEND_SMS) == PackageManager.PERMISSION_GRANTED
        }
        Log.d(TAG, "SMS permissions check result: $hasPermissions")
        return hasPermissions
    }

    private fun requestSMSPermissions(result: MethodChannel.Result) {
        Log.d(TAG, "Requesting SMS permissions")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(
                    Manifest.permission.SEND_SMS,
                    Manifest.permission.READ_SMS,
                    Manifest.permission.RECEIVE_SMS
                ),
                SMS_PERMISSION_REQUEST
            )
        } else {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.SEND_SMS),
                SMS_PERMISSION_REQUEST
            )
        }
        result.success(true)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == SMS_PERMISSION_REQUEST) {
            val allGranted = grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED }
            Log.d(TAG, "Permission request result: $allGranted")
            if (allGranted) {
                Toast.makeText(this, "Permissions granted", Toast.LENGTH_SHORT).show()
            } else {
                Toast.makeText(this, "Permissions required for emergency alerts", Toast.LENGTH_LONG).show()
                // Open app settings if permissions are permanently denied
                if (permissions.any { !shouldShowRequestPermissionRationale(it) }) {
                    val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                    intent.data = Uri.fromParts("package", packageName, null)
                    startActivity(intent)
                }
            }
        }
    }
} 