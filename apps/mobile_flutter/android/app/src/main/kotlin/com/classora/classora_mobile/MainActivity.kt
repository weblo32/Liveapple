package com.classora.classora_mobile

import android.Manifest
import android.app.PictureInPictureParams
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.os.Build
import android.util.Rational
import android.view.WindowManager
import androidx.annotation.NonNull
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val PIP_CHANNEL = "com.classora.app/pip"
    private val SECURITY_CHANNEL = "com.classora.app/security"
    private val SCREENSHARE_CHANNEL = "com.classora.app/screenshare"

    private var pipChannel: MethodChannel? = null
    private var securityChannel: MethodChannel? = null
    private var screenshareChannel: MethodChannel? = null

    private var pendingPermissionResult: MethodChannel.Result? = null
    private val REQUEST_NOTIF_CODE = 8011

    companion object {
        private var instance: MainActivity? = null

        fun notifyScreenShareServiceReady() {
            instance?.runOnUiThread {
                instance?.screenshareChannel?.invokeMethod("onServiceReady", true)
            }
        }

        fun notifyScreenShareServiceError(error: String) {
            instance?.runOnUiThread {
                instance?.screenshareChannel?.invokeMethod("onServiceError", error)
            }
        }
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        instance = this

        // 1. Screen Security Channel
        securityChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SECURITY_CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "setSecure" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        if (enabled) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        }
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
        }

        // 2. Picture-in-Picture Channel
        pipChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PIP_CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "isPipSupported" -> {
                        val supported = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                                packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)
                        result.success(supported)
                    }
                    "enterPip" -> {
                        val width = call.argument<Int>("width") ?: 16
                        val height = call.argument<Int>("height") ?: 9

                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            try {
                                val paramsBuilder = PictureInPictureParams.Builder()
                                    .setAspectRatio(Rational(width, height))
                                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                                    paramsBuilder.setAutoEnterEnabled(true)
                                }
                                val entered = enterPictureInPictureMode(paramsBuilder.build())
                                result.success(entered)
                            } catch (e: Exception) {
                                result.error("PIP_ERROR", e.localizedMessage, null)
                            }
                        } else {
                            result.success(false)
                        }
                    }
                    "isPipActive" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                            result.success(isInPictureInPictureMode)
                        } else {
                            result.success(false)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        }

        // 3. Screen Share & Foreground Service Channel
        screenshareChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SCREENSHARE_CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestNotificationPermission" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            val granted = ContextCompat.checkSelfPermission(
                                this@MainActivity,
                                Manifest.permission.POST_NOTIFICATIONS
                            ) == PackageManager.PERMISSION_GRANTED

                            if (granted) {
                                result.success(true)
                            } else {
                                pendingPermissionResult = result
                                requestPermissions(
                                    arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                                    REQUEST_NOTIF_CODE
                                )
                            }
                        } else {
                            result.success(true)
                        }
                    }
                    "startService" -> {
                        try {
                            val intent = Intent(this@MainActivity, MediaProjectionService::class.java).apply {
                                action = MediaProjectionService.ACTION_START
                            }
                            ContextCompat.startForegroundService(this@MainActivity, intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("SERVICE_START_FAILED", e.localizedMessage, null)
                        }
                    }
                    "stopService" -> {
                        try {
                            val intent = Intent(this@MainActivity, MediaProjectionService::class.java).apply {
                                action = MediaProjectionService.ACTION_STOP
                            }
                            startService(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("SERVICE_STOP_FAILED", e.localizedMessage, null)
                        }
                    }
                    "isServiceRunning" -> {
                        result.success(MediaProjectionService.isRunning)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_NOTIF_CODE) {
            val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
            pendingPermissionResult?.success(granted)
            pendingPermissionResult = null
        }
    }

    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: Configuration) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        pipChannel?.invokeMethod("onPipModeChanged", isInPictureInPictureMode)
    }

    override fun onDestroy() {
        if (instance == this) {
            instance = null
        }
        super.onDestroy()
    }
}
