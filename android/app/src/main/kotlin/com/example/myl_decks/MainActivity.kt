package com.example.myl_decks

import android.os.Bundle
import android.view.View
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsAnimationCompat
import androidx.core.view.WindowInsetsCompat
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Cancela la animación del teclado al instante para que suba/baje
        // sin el slide lento que genera MIUI / WindowInsetsAnimation.
        val root = window.decorView.rootView
        ViewCompat.setWindowInsetsAnimationCallback(
            root,
            object : WindowInsetsAnimationCompat.Callback(DISPATCH_MODE_STOP) {
                override fun onProgress(
                    insets: WindowInsetsCompat,
                    runningAnimations: MutableList<WindowInsetsAnimationCompat>
                ): WindowInsetsCompat {
                    // Terminar cada animación IME inmediatamente
                    runningAnimations
                        .filter { it.typeMask and WindowInsetsCompat.Type.ime() != 0 }
                        .forEach { it.fraction = 1f }
                    return insets
                }

                override fun onEnd(animation: WindowInsetsAnimationCompat) {
                    super.onEnd(animation)
                }
            }
        )
    }
}
