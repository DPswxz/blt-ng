package com.kkkunny.blt

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodChannel
import java.io.File

internal class AppUpdateInstaller(private val activity: Activity) {
    @Suppress("DEPRECATION")
    private fun validate(file: File, version: String, expectedCode: Long) {
        val directory = File(activity.cacheDir, "updates").canonicalFile
        require(file.parentFile == directory && file.extension == "apk" && file.isFile) {
            "找不到已下载的安装包"
        }
        val pm = activity.packageManager
        val installed = pm.getPackageInfo(activity.packageName, PackageManager.GET_SIGNATURES)
        val archive = pm.getPackageArchiveInfo(file.path, PackageManager.GET_SIGNATURES)
            ?: throw IllegalArgumentException("安装包无法解析")
        require(archive.packageName == installed.packageName) { "安装包与当前应用不匹配" }
        require(archive.versionName == version && versionCode(archive) == expectedCode &&
            expectedCode > versionCode(installed)) {
            "安装包版本与更新信息不匹配"
        }
        val signatures = installed.signatures?.toSet().orEmpty()
        require(signatures.isNotEmpty() && archive.signatures?.toSet() == signatures) {
            "安装包签名与当前应用不一致"
        }
    }

    @Suppress("DEPRECATION")
    private fun versionCode(info: PackageInfo): Long =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) info.longVersionCode
        else info.versionCode.toLong()

    fun install(path: String, version: String, expectedCode: Long, result: MethodChannel.Result) {
        Thread {
            try {
                val file = File(path).canonicalFile
                validate(file, version, expectedCode)
                activity.runOnUiThread {
                    try {
                        launchInstaller(file, result)
                    } catch (_: Exception) {
                        result.error("installer", "电视无法打开系统安装器或安装权限设置", null)
                    }
                }
            } catch (error: Exception) {
                activity.runOnUiThread {
                    val message = if (error is IllegalArgumentException) error.message else null
                    result.error("invalid_apk", message ?: "无法校验安装包", null)
                }
            }
        }.start()
    }

    private fun launchInstaller(file: File, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !activity.packageManager.canRequestPackageInstalls()
        ) {
            activity.startActivity(Intent(
                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:${activity.packageName}")
            ))
            result.success(false)
            return
        }
        val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.updates", file)
        activity.startActivity(Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        })
        result.success(true)
    }
}
