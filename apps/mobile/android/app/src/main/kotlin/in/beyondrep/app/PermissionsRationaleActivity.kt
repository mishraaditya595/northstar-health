package `in`.beyondrep.app

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Bundle

/**
 * Health Connect opens this screen when the user asks why BeyondRep wants
 * health data (Android 13 and lower: ACTION_SHOW_PERMISSIONS_RATIONALE;
 * Android 14+: the ViewPermissionUsageActivity alias). Play requires it to
 * show the app's privacy policy, so it opens the policy page and closes.
 * Without a browser it falls back to opening the app.
 */
class PermissionsRationaleActivity : Activity() {
    companion object {
        const val PRIVACY_POLICY_URL = "https://beyondrep.in/privacy"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val policy = Intent(Intent.ACTION_VIEW, Uri.parse(PRIVACY_POLICY_URL))
            .addCategory(Intent.CATEGORY_BROWSABLE)
        try {
            startActivity(policy)
        } catch (_: ActivityNotFoundException) {
            startActivity(Intent(this, MainActivity::class.java))
        }
        finish()
    }
}
