package com.example.janitra

import com.android.apksig.ApkVerifier
import java.io.File
import java.security.MessageDigest

internal object ApkUpdateVerifier {
    fun digest(bytes: ByteArray): String = MessageDigest.getInstance("SHA-256")
        .digest(bytes).joinToString("") { "%02x".format(it) }

    fun verify(
        file: File,
        expectedHash: String,
        expectedSize: Long,
        expectedVersion: String,
        apkPackage: String,
        installedPackage: String,
        apkVersion: String?,
        apkCode: Long,
        installedCode: Long,
        installedSigners: Set<String>,
        sdk: Int,
    ) {
        require(expectedHash.matches(Regex("[a-f0-9]{64}")))
        require(expectedSize in 1..536870912 && file.length() == expectedSize)
        val hash = MessageDigest.getInstance("SHA-256")
        file.inputStream().buffered().use { input ->
            val buffer = ByteArray(65536)
            while (true) {
                val count = input.read(buffer)
                if (count == -1) break
                hash.update(buffer, 0, count)
            }
        }
        val expected = expectedHash.chunked(2).map { it.toInt(16).toByte() }.toByteArray()
        require(MessageDigest.isEqual(hash.digest(), expected))
        require(apkPackage == installedPackage && apkVersion == expectedVersion)
        require(apkCode > installedCode)
        val result = ApkVerifier.Builder(file)
            .setMinCheckedPlatformVersion(sdk).setMaxCheckedPlatformVersion(sdk)
            .build().verify()
        require(result.isVerified)
        val signers = result.signerCertificates.map { digest(it.encoded) }.toSet()
        // Fail closed on signing-key rotation; release updates must use the installed key.
        require(installedSigners.isNotEmpty() && signers == installedSigners)
    }
}
