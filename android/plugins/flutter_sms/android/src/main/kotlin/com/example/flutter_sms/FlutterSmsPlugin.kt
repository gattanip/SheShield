package com.example.flutter_sms

import android.annotation.TargetApi
import android.app.Activity
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.telephony.SmsManager
import android.util.Log
import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

class FlutterSmsPlugin: FlutterPlugin, MethodCallHandler, ActivityAware {
  private lateinit var channel: MethodChannel
  private lateinit var context: Context
  private var activity: Activity? = null
  private var pendingResult: Result? = null
  private var message: String? = null
  private var recipients: List<String> = emptyList()
  private var sendDirect: Boolean = false
  private val REQUEST_CODE_SEND_SMS = 205
  private val SMS_TIMEOUT_MS = 30000L // 30 seconds timeout
  private var smsTimeoutHandler: android.os.Handler? = null

  private fun clearPendingResult() {
    pendingResult = null
    smsTimeoutHandler?.removeCallbacksAndMessages(null)
    smsTimeoutHandler = null
  }

  override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, "flutter_sms")
    channel.setMethodCallHandler(this)
    context = flutterPluginBinding.applicationContext
  }

  override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
    when (call.method) {
      "sendSMS" -> {
        if (pendingResult != null) {
          // Clear any existing pending result before starting a new one
          clearPendingResult()
        }
        
        pendingResult = result
        message = call.argument("message")
        
        // Safely handle recipients parameter
        val recipientsArg = call.argument<Any>("recipients")
        recipients = when (recipientsArg) {
          is List<*> -> recipientsArg.filterIsInstance<String>()
          is String -> listOf(recipientsArg)
          else -> {
            result.error("INVALID_RECIPIENTS", "Recipients must be a list of strings or a single string", null)
            clearPendingResult()
            return
          }
        }
        
        sendDirect = call.argument("sendDirect") ?: false
        if (message == null) {
          result.error("MISSING_PARAMS", "Message parameter is missing", null)
          clearPendingResult()
          return
        }
        if (recipients.isEmpty()) {
          result.error("MISSING_PARAMS", "Recipients parameter is missing or empty", null)
          clearPendingResult()
          return
        }

        // Set up timeout handler
        smsTimeoutHandler = android.os.Handler(android.os.Looper.getMainLooper())
        smsTimeoutHandler?.postDelayed({
          if (pendingResult != null) {
            Log.e("FlutterSmsPlugin", "SMS sending timed out after ${SMS_TIMEOUT_MS}ms")
            pendingResult?.error("TIMEOUT", "SMS sending timed out", null)
            clearPendingResult()
          }
        }, SMS_TIMEOUT_MS)

        sendSMS()
      }
      "canSendSMS" -> result.success(canSendSMS())
      else -> result.notImplemented()
    }
  }

  private fun sendSMS() {
    val sentIntent = Intent("SMS_SENT")
    val sentPI = PendingIntent.getBroadcast(
      context,
      0,
      sentIntent,
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
      } else {
        PendingIntent.FLAG_UPDATE_CURRENT
      }
    )

    var smsSentCount = 0
    val totalRecipients = recipients.size
    var hasError = false
    var receiver: BroadcastReceiver? = null

    try {
      receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
          try {
            smsSentCount++
            when (resultCode) {
              Activity.RESULT_OK -> {
                Log.d("FlutterSmsPlugin", "SMS sent successfully to recipient $smsSentCount of $totalRecipients")
                if (smsSentCount >= totalRecipients && !hasError) {
                  pendingResult?.success("SMS Sent")
                  clearPendingResult()
                  context.unregisterReceiver(this)
                }
              }
              else -> {
                hasError = true
                val errorMessage = when (resultCode) {
                  SmsManager.RESULT_ERROR_GENERIC_FAILURE -> "SMS generic failure"
                  SmsManager.RESULT_ERROR_NO_SERVICE -> "SMS no service"
                  SmsManager.RESULT_ERROR_NULL_PDU -> "SMS null PDU"
                  SmsManager.RESULT_ERROR_RADIO_OFF -> "SMS radio off"
                  else -> "Unknown SMS error"
                }
                Log.e("FlutterSmsPlugin", "SMS sending failed: $errorMessage")
                pendingResult?.error("SMS_ERROR", errorMessage, null)
                clearPendingResult()
                context.unregisterReceiver(this)
              }
            }
          } catch (e: Exception) {
            Log.e("FlutterSmsPlugin", "Error in broadcast receiver: ${e.message}")
            pendingResult?.error("SMS_ERROR", "Error processing SMS status: ${e.message}", null)
            clearPendingResult()
            try {
              context.unregisterReceiver(this)
            } catch (e: Exception) {
              Log.e("FlutterSmsPlugin", "Error unregistering receiver: ${e.message}")
            }
          }
        }
      }

      context.registerReceiver(
        receiver,
        IntentFilter("SMS_SENT"),
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
          Context.RECEIVER_EXPORTED
        } else {
          Context.RECEIVER_VISIBLE_TO_INSTANT_APPS
        }
      )

      val smsManager = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        context.getSystemService(SmsManager::class.java)
      } else {
        @Suppress("DEPRECATION")
        SmsManager.getDefault()
      }

      if (sendDirect) {
        recipients.forEach { recipient ->
          try {
            Log.d("FlutterSmsPlugin", "Attempting to send SMS to $recipient")
            smsManager.sendTextMessage(recipient, null, message, sentPI, null)
          } catch (e: Exception) {
            Log.e("FlutterSmsPlugin", "Error sending SMS to $recipient: ${e.message}")
            hasError = true
          }
        }
      } else {
        val intent = Intent(Intent.ACTION_SENDTO)
        intent.data = Uri.parse("smsto:${recipients.joinToString(";")}")
        intent.putExtra("sms_body", message)
        activity?.startActivity(intent)
        pendingResult?.success("SMS Sent")
        clearPendingResult()
      }
    } catch (e: Exception) {
      Log.e("FlutterSmsPlugin", "Error in sendSMS: ${e.message}")
      pendingResult?.error("SMS_ERROR", e.message, null)
      clearPendingResult()
      receiver?.let {
        try {
          context.unregisterReceiver(it)
        } catch (e: Exception) {
          Log.e("FlutterSmsPlugin", "Error unregistering receiver: ${e.message}")
        }
      }
    }
  }

  override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
    clearPendingResult()
  }

  override fun onAttachedToActivity(binding: ActivityPluginBinding) {
    activity = binding.activity
  }

  override fun onDetachedFromActivityForConfigChanges() {
    activity = null
  }

  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
    activity = binding.activity
  }

  override fun onDetachedFromActivity() {
    activity = null
  }

  @TargetApi(Build.VERSION_CODES.ECLAIR)
  private fun canSendSMS(): Boolean {
    if (!activity!!.packageManager.hasSystemFeature(PackageManager.FEATURE_TELEPHONY))
      return false
    val intent = Intent(Intent.ACTION_SENDTO)
    intent.data = Uri.parse("smsto:")
    val activityInfo = intent.resolveActivityInfo(activity!!.packageManager, intent.flags.toInt())
    return !(activityInfo == null || !activityInfo.exported)
  }
}
