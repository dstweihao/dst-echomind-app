package com.dstweihao.echomind

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    companion object {
        private const val UPDATER_CHANNEL = "com.dstweihao.echomind/updater"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, UPDATER_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "installApk" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrBlank()) {
                            result.error("INVALID_ARG", "APK 路径为空", null)
                            return@setMethodCallHandler
                        }
                        handleInstallApk(path, result)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun handleInstallApk(path: String, result: MethodChannel.Result) {
        val apkFile = File(path)
        if (!apkFile.exists()) {
            result.error("NOT_FOUND", "安装包文件不存在", null)
            return
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !packageManager.canRequestPackageInstalls()
        ) {
            try {
                val permIntent = Intent(
                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:$packageName"),
                ).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                startActivity(permIntent)
                result.success("needs_permission")
            } catch (e: Exception) {
                result.error("PERM_ERROR", e.message ?: "无法打开安装权限设置", null)
            }
            return
        }

        try {
            val contentUri = FileProvider.getUriForFile(
                this,
                "$packageName.update_fileprovider",
                apkFile,
            )
            val installIntent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(contentUri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(installIntent)
            result.success("launched")
        } catch (e: Exception) {
            result.error("INSTALL_ERROR", e.message ?: "无法启动系统安装程序", null)
        }
    }
}
