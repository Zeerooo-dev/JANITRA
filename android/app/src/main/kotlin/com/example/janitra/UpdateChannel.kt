package com.example.janitra

import android.app.Activity
import android.content.ClipData
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.StatFs
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

internal class UpdateChannel(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "janitra/updates")
    private val executor = Executors.newSingleThreadExecutor()
    var foreground = false
    private val directory get() = File(activity.cacheDir, "updates").apply { mkdirs() }

    init {
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "info" -> {
                        val app = installed()
                        result.success(mapOf(
                            "version" to app.versionName,
                            "directory" to directory.absolutePath,
                            "freeBytes" to StatFs(directory.path).availableBytes,
                        ))
                    }
                    "canInstall" -> result.success(canInstall())
                    "permission" -> {
                        check(foreground)
                        if (Build.VERSION.SDK_INT >= 26 && !canInstall()) {
                            activity.startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                Uri.parse("package:${activity.packageName}")))
                        }
                        result.success(null)
                    }
                    "verify", "install" -> verifyAsync(call, result)
                    else -> result.notImplemented()
                }
            } catch (_: Exception) {
                result.error(if (call.method == "permission") "permission" else "unavailable", "Update action unavailable", null)
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun installed(): PackageInfo = activity.packageManager.getPackageInfo(
        activity.packageName,
        if (Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES else PackageManager.GET_SIGNATURES,
    )

    @Suppress("DEPRECATION")
    private fun code(info: PackageInfo): Long = if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()

    private fun canInstall(): Boolean = Build.VERSION.SDK_INT < 26 || activity.packageManager.canRequestPackageInstalls()

    @Suppress("DEPRECATION")
    private fun verify(call: MethodCall): File {
        val root = directory.canonicalFile
        val file = File(requireNotNull(call.argument<String>("path"))).canonicalFile
        require(file.parentFile == root && file.name.matches(Regex("[0-9]+\\.apk")) && file.isFile)
        val size = requireNotNull(call.argument<Number>("size")).toLong()
        if (StatFs(root.path).availableBytes < size * 2 + 32 * 1024 * 1024) {
            throw StorageException()
        }
        val current = installed()
        val signatures = if (Build.VERSION.SDK_INT >= 28) current.signingInfo?.apkContentsSigners else current.signatures
        val candidate = requireNotNull(activity.packageManager.getPackageArchiveInfo(file.path, 0))
        val appInfo = requireNotNull(candidate.applicationInfo)
        require(appInfo.minSdkVersion <= Build.VERSION.SDK_INT)
        ApkUpdateVerifier.verify(
            file, requireNotNull(call.argument<String>("sha256")), size,
            requireNotNull(call.argument<String>("version")), candidate.packageName, activity.packageName,
            candidate.versionName, code(candidate), code(current),
            signatures?.map { ApkUpdateVerifier.digest(it.toByteArray()) }?.toSet() ?: emptySet(),
            Build.VERSION.SDK_INT,
        )
        require(file.setReadOnly())
        return file
    }

    private fun verifyAsync(call: MethodCall, result: MethodChannel.Result) {
        executor.execute {
            try {
                val file = verify(call)
                activity.runOnUiThread {
                    if (call.method == "verify") result.success(null)
                    else if (!foreground || activity.isFinishing || activity.isDestroyed) {
                        result.error("installer", "Return to JANITRA before installing", null)
                    } else if (!canInstall()) {
                        result.error("permission", "Installation permission required", null)
                    } else {
                        try {
                            val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.updates", file)
                            // Use Android's installer action rather than offering APK file browsers.
                            @Suppress("DEPRECATION")
                            val intent = Intent(Intent.ACTION_INSTALL_PACKAGE).apply {
                                setDataAndType(uri, "application/vnd.android.package-archive")
                                clipData = ClipData.newRawUri("JANITRA update", uri)
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            }
                            activity.startActivity(intent)
                            result.success(null)
                        } catch (_: Exception) {
                            result.error("installer", "Android installer unavailable", null)
                        }
                    }
                }
            } catch (error: Exception) {
                activity.runOnUiThread {
                    result.error(if (error is StorageException) "storage" else "verification", "APK verification failed", null)
                }
            }
        }
    }

    fun close() {
        channel.setMethodCallHandler(null)
        executor.shutdown()
    }

    private class StorageException : Exception()
}
