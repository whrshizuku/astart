package com.start.notes

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.media.MediaPlayer
import android.os.Build
import android.os.Bundle
import android.os.VibrationEffect
import android.os.Vibrator
import android.provider.AlarmClock
import android.provider.CalendarContract
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.view.WindowManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.text.BreakIterator
import java.util.TimeZone
import java.util.Calendar
import java.util.Locale

/**
 * 原生通道层：偏好读写 / 中文分词 / 音效震动 / 系统信息 / 任意门动作 / 日历闹钟 / 语音识别。
 * prefs 直接走同名 SharedPreferences，保证与老 Java 版数据完全兼容。
 */
class MainActivity : FlutterActivity() {

    private var chime: MediaPlayer? = null
    private var boot: MediaPlayer? = null
    private var voice: VoiceChannel? = null
    private var pendingResult: MethodChannel.Result? = null
    private var pendingExportJson: String? = null

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        val m = engine.dartExecutor.binaryMessenger

        MethodChannel(m, "start/prefs").setMethodCallHandler { call, result ->
            val sp = getSharedPreferences(call.argument<String>("name") ?: "start_prefs", MODE_PRIVATE)
            when (call.method) {
                "getAll" -> result.success(sp.all)
                "set" -> {
                    val key = call.argument<String>("key") ?: return@setMethodCallHandler result.error("args", "key required", null)
                    val value = call.argument<Any?>("value")
                    val e = sp.edit()
                    when (value) {
                        null -> e.remove(key)
                        is Boolean -> e.putBoolean(key, value)
                        is Int -> e.putInt(key, value)
                        is Long -> e.putLong(key, value)
                        is Double -> e.putFloat(key, value.toFloat())
                        is String -> e.putString(key, value)
                        else -> return@setMethodCallHandler result.error("type", "unsupported ${value?.javaClass}", null)
                    }
                    e.apply()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(m, "start/segment").setMethodCallHandler { call, result ->
            when (call.method) {
                "words" -> result.success(segmentWords(call.argument<String>("text") ?: ""))
                else -> result.notImplemented()
            }
        }

        MethodChannel(m, "start/sound").setMethodCallHandler { call, result ->
            when (call.method) {
                "tick" -> {
                    playTick((call.argument<Int>("volume") ?: 70).coerceIn(0, 100))
                    result.success(null)
                }
                "chime" -> {
                    stopChime()
                    try {
                        chime = MediaPlayer.create(this, R.raw.finish_chime)?.apply {
                            setOnCompletionListener { mp ->
                                try { mp.release() } catch (_: Exception) {}
                                chime = null
                            }
                            start()
                        }
                    } catch (_: Exception) {}
                    result.success(null)
                }
                "stopChime" -> { stopChime(); result.success(null) }
                "playBoot" -> {
                    val sp = getSharedPreferences("start_prefs", MODE_PRIVATE)
                    if (sp.getBoolean("boot_sound_on", false)) {
                        val vol = (sp.getInt("sound_volume", 70) / 100f)
                        playBoot(java.io.File(filesDir, "boot_sound.mp3"), vol)
                    }
                    result.success(null)
                }
                "previewBoot" -> {
                    val vol = ((call.argument<Int>("volume") ?: 70).coerceIn(0, 100)) / 100f
                    playBoot(java.io.File(filesDir, "boot_sound.mp3"), vol)
                    result.success(null)
                }
                "stopBoot" -> { stopBoot(); result.success(null) }
                else -> result.notImplemented()
            }
        }

        MethodChannel(m, "start/system").setMethodCallHandler { call, result ->
            when (call.method) {
                "filesDir" -> result.success(filesDir.absolutePath)
                "versionName" -> result.success(
                    try {
                        packageManager.getPackageInfo(packageName, 0).versionName
                    } catch (_: Exception) {
                        null
                    }
                )
                "calendarInsert" -> {
                    val title = call.argument<String>("title") ?: ""
                    // Dart 毫秒时间戳是 64 位，按值域编码为 Int 或 Long，须安全读取。
                    val msRaw = call.argument<Any>("ms")
                    val ms = (msRaw as? Long) ?: (msRaw as? Int)?.toLong() ?: 0L
                    if (ContextCompat.checkSelfPermission(this, Manifest.permission.WRITE_CALENDAR)
                        != PackageManager.PERMISSION_GRANTED
                    ) {
                        ActivityCompat.requestPermissions(
                            this,
                            arrayOf(Manifest.permission.WRITE_CALENDAR, Manifest.permission.READ_CALENDAR),
                            211
                        )
                        result.success(0)
                    } else {
                        try {
                            // 取第一个可写日历（贡献者权限以上）。
                            var calId = -1L
                            contentResolver.query(
                                CalendarContract.Calendars.CONTENT_URI,
                                arrayOf(
                                    CalendarContract.Calendars._ID,
                                    CalendarContract.Calendars.CALENDAR_ACCESS_LEVEL
                                ),
                                "${CalendarContract.Calendars.VISIBLE} = 1", null,
                                "${CalendarContract.Calendars._ID} ASC"
                            )?.use { cur ->
                                while (cur.moveToNext()) {
                                    // CALENDAR_ACCESS_LEVEL >= CONTRIBUTOR(500) 才可写。
                                    if (cur.getInt(1) >= 500) {
                                        calId = cur.getLong(0)
                                        break
                                    }
                                }
                            }
                            if (calId <= 0) {
                                result.success(0)
                            } else {
                                val cv = ContentValues().apply {
                                    put(CalendarContract.Events.CALENDAR_ID, calId)
                                    put(CalendarContract.Events.TITLE, title)
                                    put(CalendarContract.Events.DTSTART, ms)
                                    put(CalendarContract.Events.DTEND, ms + 60 * 60 * 1000)
                                    put(CalendarContract.Events.EVENT_TIMEZONE, TimeZone.getDefault().id)
                                }
                                val uri = contentResolver.insert(CalendarContract.Events.CONTENT_URI, cv)
                                result.success(uri?.lastPathSegment?.toLongOrNull() ?: 0)
                            }
                        } catch (_: Exception) {
                            result.success(0)
                        }
                    }
                }
                "vibrate" -> {
                    vibrate((call.argument<Int>("ms") ?: 20).toLong())
                    result.success(null)
                }
                "keepScreenOn" -> {
                    if (call.argument<Boolean>("on") == true)
                        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    else
                        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    result.success(null)
                }
                "initialShare" -> result.success(
                    intent?.takeIf { it.action == Intent.ACTION_SEND }?.getStringExtra(Intent.EXTRA_TEXT)
                )
                "openAction" -> {
                    val kind = call.argument<String>("kind")
                    val data = call.argument<String>("data") ?: ""
                    try {
                        when (kind) {
                            "dial" -> startActivity(Intent(Intent.ACTION_DIAL, android.net.Uri.parse("tel:${android.net.Uri.encode(data)}")))
                            "url" -> startActivity(Intent(Intent.ACTION_VIEW, android.net.Uri.parse(data)))
                            else -> {
                                result.notImplemented()
                                return@setMethodCallHandler
                            }
                        }
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("open", e.message, null)
                    }
                }
                "calendar" -> {
                    val title = call.argument<String>("title") ?: ""
                    val msRaw = call.argument<Any>("ms")
                    val ms = (msRaw as? Long) ?: (msRaw as? Int)?.toLong() ?: 0L
                    try {
                        val cal = Calendar.getInstance().apply { timeInMillis = ms }
                        val i = Intent(Intent.ACTION_INSERT).apply {
                            data = CalendarContract.Events.CONTENT_URI
                            putExtra(CalendarContract.Events.TITLE, title)
                            putExtra(CalendarContract.EXTRA_EVENT_BEGIN_TIME, ms)
                            putExtra(CalendarContract.EXTRA_EVENT_END_TIME, ms + 60 * 60 * 1000)
                        }
                        startActivity(i)
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("calendar", e.message, null)
                    }
                }
                "alarm" -> {
                    val title = call.argument<String>("title") ?: ""
                    val msRaw = call.argument<Any>("ms")
                    val ms = (msRaw as? Long) ?: (msRaw as? Int)?.toLong() ?: 0L
                    try {
                        val cal = Calendar.getInstance().apply { timeInMillis = ms }
                        val i = Intent(AlarmClock.ACTION_SET_ALARM).apply {
                            putExtra(AlarmClock.EXTRA_MESSAGE, title)
                            putExtra(AlarmClock.EXTRA_HOUR, cal.get(Calendar.HOUR_OF_DAY))
                            putExtra(AlarmClock.EXTRA_MINUTES, cal.get(Calendar.MINUTE))
                            putExtra(AlarmClock.EXTRA_SKIP_UI, true)
                        }
                        startActivity(i)
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("alarm", e.message, null)
                    }
                }
                "notifySchedule" -> {
                    val id = call.argument<Int>("id") ?: 0
                    val label = call.argument<String>("label") ?: ""
                    val w = call.argument<Any>("when")
                    val whenMs = (w as? Long) ?: (w as? Int)?.toLong() ?: 0L
                    ReminderAlarm.schedule(this, id, label, whenMs)
                    result.success(null)
                }
                "notifyCancel" -> {
                    ReminderAlarm.cancel(this, call.argument<Int>("id") ?: 0)
                    result.success(null)
                }
                "setKeepAlive" -> {
                    if (call.argument<Boolean>("on") == true) startOngoing()
                    else (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                        .cancel(ReminderAlarm.ONGOING_ID)
                    result.success(null)
                }
                "calendarToday" -> {
                    if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_CALENDAR)
                            != PackageManager.PERMISSION_GRANTED) {
                        ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.READ_CALENDAR), 210)
                        result.success(emptyList<Map<String, Any>>())
                    } else {
                        result.success(readCalendarToday())
                    }
                }
                else -> result.notImplemented()
            }
        }

        voice = VoiceChannel(this, m)

        // SAF 文件导入导出：ACTION_CREATE_DOCUMENT / ACTION_OPEN_DOCUMENT
        MethodChannel(m, "start/file").setMethodCallHandler { call, result ->
            when (call.method) {
                "export" -> {
                    pendingExportJson = call.argument<String>("json")
                    pendingResult = result
                    val name = call.argument<String>("name") ?: "start_data.json"
                    try {
                        val i = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "application/json"
                            putExtra(Intent.EXTRA_TITLE, name)
                        }
                        startActivityForResult(i, 9999)
                    } catch (e: Exception) {
                        pendingExportJson = null
                        pendingResult = null
                        result.error("export", e.message, null)
                    }
                }
                "import" -> {
                    pendingResult = result
                    try {
                        val i = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "application/json"
                        }
                        startActivityForResult(i, 9998)
                    } catch (e: Exception) {
                        pendingResult = null
                        result.error("import", e.message, null)
                    }
                }
                "pickBootSound" -> {
                    pendingResult = result
                    try {
                        val i = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "audio/*"
                        }
                        startActivityForResult(i, 9997)
                    } catch (e: Exception) {
                        pendingResult = null
                        result.error("pickBootSound", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Android 13+ 通知权限：进 App 即请求，拒绝只影响悬浮提醒，不影响其他功能。
        if (Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS)
                != PackageManager.PERMISSION_GRANTED) {
            ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.POST_NOTIFICATIONS), 2101)
        }
        try { startOngoing() } catch (_: Exception) {}
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == 9999) {
            // 导出：写文件
            val json = pendingExportJson
            val r = pendingResult
            pendingExportJson = null
            pendingResult = null
            if (resultCode == RESULT_OK && data?.data != null && json != null) {
                try {
                    contentResolver.openOutputStream(data.data!!)?.use { os ->
                        os.write(json.toByteArray(Charsets.UTF_8))
                    }
                    r?.success(true)
                } catch (e: Exception) {
                    r?.error("export", e.message, null)
                }
            } else {
                r?.success(false)
            }
        } else if (requestCode == 9998) {
            // 导入：读文件
            val r = pendingResult
            pendingResult = null
            if (resultCode == RESULT_OK && data?.data != null) {
                try {
                    val text = contentResolver.openInputStream(data.data!!)?.use { ins ->
                        ins.readBytes().toString(Charsets.UTF_8)
                    }
                    r?.success(text)
                } catch (e: Exception) {
                    r?.error("import", e.message, null)
                }
            } else {
                r?.success(null)
            }
        } else if (requestCode == 9997) {
            // 开机铃声：把所选音频复制到 filesDir/boot_sound.mp3
            val r = pendingResult
            pendingResult = null
            var ok = false
            if (resultCode == RESULT_OK && data?.data != null) {
                try {
                    contentResolver.openInputStream(data.data!!)?.use { ins ->
                        java.io.File(filesDir, "boot_sound.mp3").outputStream().use { os ->
                            ins.copyTo(os)
                        }
                    }
                    ok = true
                } catch (_: Exception) {}
            }
            r?.success(ok)
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    private fun stopChime() {
        chime?.let {
            try { if (it.isPlaying) it.stop() } catch (_: Exception) {}
            try { it.release() } catch (_: Exception) {}
        }
        chime = null
    }

    /** 自定义开机铃声：优先播放 filesDir/boot_sound.mp3；文件不存在时回退内置提示音。 */
    private fun playBoot(f: java.io.File, volume: Float) {
        stopBoot()
        try {
            boot = if (f.exists()) MediaPlayer().apply {
                setDataSource(f.absolutePath)
                setVolume(volume, volume)
                setOnCompletionListener { mp -> try { mp.release() } catch (_: Exception) {}; boot = null }
                prepare()
                start()
            } else MediaPlayer.create(this, R.raw.finish_chime)?.apply {
                setVolume(volume, volume)
                setOnCompletionListener { mp -> try { mp.release() } catch (_: Exception) {}; boot = null }
                start()
            }
        } catch (_: Exception) {}
    }

    private fun stopBoot() {
        boot?.let {
            try { if (it.isPlaying) it.stop() } catch (_: Exception) {}
            try { it.release() } catch (_: Exception) {}
        }
        boot = null
    }

    /**
     * 专注滴答：AudioTrack 直接播放程序生成的一声短音（80ms，900Hz，指数衰减），
     * 走媒体流——不依赖 ToneGenerator（不少 ROM 上系统流静音/勿扰时静默失败），
     * 设置里的提示音量线性生效。播完在标记回调里自释放。
     */
    private fun playTick(volume0to100: Int) {
        if (volume0to100 <= 0) return
        try {
            val rate = 44100
            val samples = (rate * 0.08).toInt()
            val gain = volume0to100 / 100f * 0.9f
            val pcm = ShortArray(samples)
            for (i in 0 until samples) {
                val t = i.toDouble() / rate
                val env = Math.exp(-t / 0.035)
                val v = Math.sin(2.0 * Math.PI * 900.0 * t) * env * gain
                pcm[i] = (v * Short.MAX_VALUE).toInt().toShort()
            }
            val attrs = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
            val fmt = AudioFormat.Builder()
                .setSampleRate(rate)
                .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                .build()
            val track = AudioTrack.Builder()
                .setAudioAttributes(attrs)
                .setAudioFormat(fmt)
                .setBufferSizeInBytes(pcm.size * 2)
                .setTransferMode(AudioTrack.MODE_STATIC)
                .build()
            track.write(pcm, 0, pcm.size)
            track.setNotificationMarkerPosition(samples)
            track.setPlaybackPositionUpdateListener(object : AudioTrack.OnPlaybackPositionUpdateListener {
                override fun onMarkerReached(t: AudioTrack?) {
                    try { t?.pause(); t?.release() } catch (_: Exception) {}
                }
                override fun onPeriodicNotification(t: AudioTrack?) {}
            })
            track.play()
        } catch (_: Exception) {}
    }

    private fun vibrate(ms: Long) {
        val v = getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        if (Build.VERSION.SDK_INT >= 26) {
            v.vibrate(VibrationEffect.createOneShot(ms, VibrationEffect.DEFAULT_AMPLITUDE))
        } else {
            @Suppress("DEPRECATION") v.vibrate(ms)
        }
    }

    /** 常驻保活通知：IMPORTANCE_MIN 静默、不可滑动清除，降低后台被系统误杀概率。 */
    private fun startOngoing() {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.createNotificationChannel(
            NotificationChannel(ReminderAlarm.CHANNEL_ONGOING, "常驻守护", NotificationManager.IMPORTANCE_MIN))
        val pi = PendingIntent.getActivity(this, 0,
            packageManager.getLaunchIntentForPackage(packageName),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        nm.notify(ReminderAlarm.ONGOING_ID, Notification.Builder(this, ReminderAlarm.CHANNEL_ONGOING)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Start")
            .setContentText("今日待办守护中")
            .setOngoing(true)
            .setContentIntent(pi)
            .build())
    }

    /** 词级分词：BreakIterator ICU 词典，剥掉首尾标点，移植自老版 BigBangOverlay。 */
    private fun segmentWords(text: String): List<String> {
        val out = ArrayList<String>()
        val bi = BreakIterator.getWordInstance(Locale.CHINA)
        bi.setText(text)
        var start = bi.first()
        var end = bi.next()
        while (end != BreakIterator.DONE) {
            var w = text.substring(start, end).trim()
                .trim('，', '。', '、', '；', '：', '！', '？', ',', '.', '!', '?', ';', ':',
                    '"', '\'', '(', ')', '（', '）', '<', '>', '「', '」', '『', '』', '【', '】',
                    '[', ']', '…', '—', '·')
            if (w.isNotEmpty()) out.add(w)
            start = end
            end = bi.next()
        }
        return out
    }

    /** 读取今日手机日历事件（移植自老版 Cal.today）。返回 {id,title,begin,end,calName} 列表。 */
    private fun readCalendarToday(): List<Map<String, Any>> {
        val out = ArrayList<Map<String, Any>>()
        val now = Calendar.getInstance()
        val start = (now.clone() as Calendar).apply {
            set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
        }
        val end = (now.clone() as Calendar).apply {
            set(Calendar.HOUR_OF_DAY, 23); set(Calendar.MINUTE, 59)
            set(Calendar.SECOND, 59); set(Calendar.MILLISECOND, 999)
        }
        val proj = arrayOf(
            CalendarContract.Instances.EVENT_ID,
            CalendarContract.Instances.TITLE,
            CalendarContract.Instances.BEGIN,
            CalendarContract.Instances.END
        )
        try {
            val uri = CalendarContract.Instances.CONTENT_URI.buildUpon()
                .appendPath(start.timeInMillis.toString())
                .appendPath(end.timeInMillis.toString())
                .build()
            contentResolver.query(uri, proj, null, null,
                "${CalendarContract.Instances.BEGIN} ASC")?.use { c ->
                while (c.moveToNext()) {
                    out.add(mapOf(
                        "id" to c.getLong(0),
                        "title" to (c.getString(1) ?: ""),
                        "begin" to c.getLong(2),
                        "end" to c.getLong(3),
                        "calName" to ""
                    ))
                }
            }
        } catch (_: Exception) {
        }
        return out
    }
}

/**
 * 语音识别：Android 原生 SpeechRecognizer，离线优先（EXTRA_PREFER_OFFLINE），不联网。
 * 事件流 type: ready|partial|final|end|error；text: 识别文本。
 */
class VoiceChannel(private val ctx: Context, messenger: io.flutter.plugin.common.BinaryMessenger) {
    private var sr: SpeechRecognizer? = null
    private var sink: EventChannel.EventSink? = null

    init {
        EventChannel(messenger, "start/voice/evt").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                sink = events
            }
            override fun onCancel(arguments: Any?) {
                sink = null
                stop()
            }
        })
        MethodChannel(messenger, "start/voice").setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> { start(call.argument<Boolean>("online") == true); result.success(null) }
                "stop" -> { stop(); result.success(null) }
                else -> result.notImplemented()
            }
        }
    }

    private fun micGranted(): Boolean =
        ContextCompat.checkSelfPermission(ctx, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED

    fun start(online: Boolean = false) {
        if (!micGranted()) {
            val act = ctx as? MainActivity
            act?.let {
                ActivityCompat.requestPermissions(it, arrayOf(Manifest.permission.RECORD_AUDIO), 200)
                sink?.success(mapOf("type" to "error", "text" to "需要麦克风权限"))
                return
            }
        }
        beginListening(online)
    }

    fun beginListening(online: Boolean = false) {
        stop()
        // 不检查 isRecognitionAvailable（它只查 Google 服务）。直接尝试启动，
        // 系统枚举本机所有语音引擎（含厂商自研离线），不绑谷歌。
        // online=false（默认）强制 PREFER_OFFLINE；用户在设置里显式开启在线识别才允许走网络。
        try {
        sr = SpeechRecognizer.createSpeechRecognizer(ctx).apply {
            setRecognitionListener(object : RecognitionListener {
                override fun onReadyForSpeech(p: Bundle?) { sink?.success(mapOf("type" to "ready")) }
                override fun onBeginningOfSpeech() {}
                override fun onRmsChanged(r: Float) { sink?.success(mapOf("type" to "rms", "text" to r.toString())) }
                override fun onBufferReceived(b: ByteArray?) {}
                override fun onEndOfSpeech() { sink?.success(mapOf("type" to "end")) }
                override fun onError(e: Int) { sink?.success(mapOf("type" to "error", "text" to e.toString())) }
                override fun onResults(b: Bundle?) {
                    val list = b?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                    sink?.success(mapOf("type" to "final", "text" to (list?.firstOrNull() ?: "")))
                }
                override fun onPartialResults(b: Bundle?) {
                    val list = b?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                    sink?.success(mapOf("type" to "partial", "text" to (list?.firstOrNull() ?: "")))
                }
                override fun onEvent(e: Int, b: Bundle?) {}
            })
        }
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, "zh-CN")
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            if (Build.VERSION.SDK_INT >= 23 && !online) putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
        }
        sr?.startListening(intent)
        } catch (e: Exception) {
            sink?.success(mapOf("type" to "error", "text" to "本机无可用语音引擎，请在系统设置安装离线语音包"))
        }
    }

    fun stop() {
        try { sr?.stopListening() } catch (_: Exception) {}
        try { sr?.destroy() } catch (_: Exception) {}
        sr = null
    }
}
