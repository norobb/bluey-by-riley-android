package co.visionairy.googly

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import co.visionairy.googly.proto.PairingRecord
import org.json.JSONObject
import java.io.File
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * The phone's pairing credential, encrypted with a non-exportable Android Keystore key
 * (the counterpart of iOS's device-only Keychain item). Never log the record's secret.
 */
class PairingStore(private val context: Context) {
    private val prefs = context.getSharedPreferences("bluey", Context.MODE_PRIVATE)
    private val dir = File(context.noBackupFilesDir, "pairing").apply { mkdirs() }

    var preferredMac: String?
        get() = prefs.getString("preferredMac", null)
        set(value) { prefs.edit().putString("preferredMac", value).apply() }

    fun load(): PairingRecord? {
        val file = file(preferredMac ?: "mac")
        if (!file.exists()) return null
        return runCatching {
            val bytes = file.readBytes()
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, bytes, 0, 12))
            PairingRecord.fromJson(JSONObject(String(cipher.doFinal(bytes, 12, bytes.size - 12))))
        }.getOrNull()
    }

    fun save(record: PairingRecord): Boolean = runCatching {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key())
        val sealed = cipher.iv + cipher.doFinal(record.toJson().toString().toByteArray())
        val target = file(record.service)
        val tmp = File(dir, target.name + ".tmp")
        tmp.writeBytes(sealed)
        check(tmp.renameTo(target))
        preferredMac = record.service
    }.isSuccess

    private fun file(service: String) = File(dir, service.toByteArray().joinToString("") { "%02x".format(it) }.take(120) + ".bin")

    private fun key(): SecretKey {
        val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (ks.getKey(ALIAS, null) as? SecretKey)?.let { return it }
        val gen = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        gen.init(KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256).build())
        return gen.generateKey()
    }

    private companion object { const val ALIAS = "co.visionairy.googly.pairing" }
}
