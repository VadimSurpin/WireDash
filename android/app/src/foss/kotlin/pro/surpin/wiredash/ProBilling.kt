package pro.surpin.wiredash

import android.app.Activity
import io.flutter.plugin.common.BinaryMessenger

/**
 * The foss build (GitHub, IzzyOnDroid, F-Droid) has no billing library and
 * everything unlocked; the Dart side knows from ZIGDASH_FLAVOR and never asks.
 */
object ProBilling {
    fun register(@Suppress("UNUSED_PARAMETER") activity: Activity,
                 @Suppress("UNUSED_PARAMETER") messenger: BinaryMessenger) {}
}
