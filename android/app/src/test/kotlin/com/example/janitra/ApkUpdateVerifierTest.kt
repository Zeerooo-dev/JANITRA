package com.example.janitra

import com.android.apksig.ApkVerifier
import java.io.File
import java.security.MessageDigest
import org.junit.Assert.*
import org.junit.Test

class ApkUpdateVerifierTest {
    private val apk get() = File(requireNotNull(System.getProperty("janitra.testApk")))
    private fun hash(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().buffered().use { input ->
            val buffer = ByteArray(65536)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                digest.update(buffer, 0, count)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    private val signers get() = ApkVerifier.Builder(apk).build().verify().signerCertificates
        .map { ApkUpdateVerifier.digest(it.encoded) }.toSet()

    private fun verify(file: File = apk, checksum: String = hash(file), size: Long = file.length(),
                       pkg: String = "com.example.janitra", version: String = "1.0.0", code: Long = 26,
                       installed: Long = 25, certificates: Set<String> = signers, sdk: Int = 36) {
        ApkUpdateVerifier.verify(file, checksum, size, "1.0.0", pkg, "com.example.janitra",
            version, code, installed, certificates, sdk)
    }

    private fun rejects(block: () -> Unit) {
        try { block() } catch (_: Exception) { return }
        fail("An unsafe APK was accepted")
    }

    @Test fun acceptsAuthenticSameSignerOnSupportedAndroidVersions() {
        assertTrue("Build the release APK before running these tests", apk.isFile)
        verify(sdk = 24)
        verify(sdk = 36)
    }

    @Test fun rejectsChecksumMismatch() = rejects { verify(checksum = "0".repeat(64)) }
    @Test fun rejectsMalformedHash() = rejects { verify(checksum = "not-a-hash") }
    @Test fun rejectsSizeMismatch() = rejects { verify(size = apk.length() + 1) }
    @Test fun rejectsWrongPackage() = rejects { verify(pkg = "com.attacker.app") }
    @Test fun rejectsWrongVersion() = rejects { verify(version = "9.0.0") }
    @Test fun rejectsDowngradeAndReinstallation() {
        rejects { verify(installed = 26) }
        rejects { verify(installed = 27) }
    }
    @Test fun rejectsWrongOrAdditionalSigners() {
        rejects { verify(certificates = setOf("0".repeat(64))) }
        rejects { verify(certificates = signers + "0".repeat(64)) }
        rejects { verify(certificates = emptySet()) }
    }
    @Test fun rejectsTamperingEvenWhenAttackerChangesChecksumToo() {
        val changed = File.createTempFile("janitra-tampered", ".apk")
        try {
            apk.copyTo(changed, overwrite = true)
            java.io.RandomAccessFile(changed, "rw").use { file ->
                file.seek(1024)
                val byte = file.readByte()
                file.seek(1024)
                file.writeByte(byte.toInt() xor 1)
            }
            rejects { verify(file = changed) }
        } finally { changed.delete() }
    }
}
