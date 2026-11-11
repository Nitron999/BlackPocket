package com.example.blackpocket_ai // Если у тебя другой package, оставь свою верхнюю строчку!

import android.os.Bundle
import android.speech.tts.TextToSpeech
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

class MainActivity: FlutterActivity(), TextToSpeech.OnInitListener {
    private val CHANNEL = "blackpocket/native_tts"
    private var tts: TextToSpeech? = null
    private var isTtsReady = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        tts = TextToSpeech(this, this)
    }

    override fun onInit(status: Int) {
        if (status == TextToSpeech.SUCCESS) {
            tts?.language = Locale("ru", "RU")
            isTtsReady = true
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "speak") {
                val text = call.argument<String>("text")
                if (isTtsReady && text != null) {
                    tts?.stop()
                    tts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "BlackPocketTTS")
                    result.success(true)
                } else {
                    result.success(false)
                }
            } else {
                result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        tts?.stop()
        tts?.shutdown()
        super.onDestroy()
    }
}
