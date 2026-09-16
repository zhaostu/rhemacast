package com.rhemacast

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Slider
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1)
        }
        setContent {
            MaterialTheme {
                Surface(Modifier.fillMaxSize()) {
                    ListenerScreen()
                }
            }
        }
    }
}

@Composable
fun ListenerScreen() {
    val context = LocalContext.current
    val audio = remember {
        context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    }
    var ip by remember { mutableStateOf("192.168.4.1") }
    val status by PlaybackService.status.collectAsState()
    val stats by PlaybackService.stats.collectAsState()
    val maxVol = remember { audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC) }
    var volume by remember {
        mutableFloatStateOf(audio.getStreamVolume(AudioManager.STREAM_MUSIC).toFloat())
    }
    val playing = status.startsWith("Playing") || status.startsWith("Connecting")

    Column(
        Modifier.fillMaxSize().padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text("Rhemacast Listener", style = MaterialTheme.typography.headlineSmall)
        OutlinedTextField(
            value = ip,
            onValueChange = { ip = it.trim() },
            label = { Text("Translator IP") },
            singleLine = true,
            modifier = Modifier.fillMaxWidth(),
        )
        Text("WHEP: http://$ip:8080/whep", style = MaterialTheme.typography.bodySmall)
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Button(
                onClick = { PlaybackService.start(context, ip) },
                enabled = !playing && ip.isNotBlank(),
            ) { Text("Connect") }
            OutlinedButton(
                onClick = { PlaybackService.stop(context) },
                enabled = playing,
            ) { Text("Disconnect") }
        }
        Spacer(Modifier.height(4.dp))
        Text("Volume")
        Slider(
            value = volume,
            onValueChange = {
                volume = it
                audio.setStreamVolume(AudioManager.STREAM_MUSIC, it.toInt(), 0)
            },
            valueRange = 0f..maxVol.toFloat(),
            steps = maxVol - 1,
            modifier = Modifier.fillMaxWidth(),
        )
        Spacer(Modifier.height(4.dp))
        Text("Status: $status", style = MaterialTheme.typography.bodyLarge)
        if (stats.isNotEmpty()) Text(stats, style = MaterialTheme.typography.bodyMedium)
        Spacer(Modifier.height(4.dp))
        Text("Translator", style = MaterialTheme.typography.titleSmall)
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            OutlinedButton(onClick = {
                val host = ip.ifBlank { "192.168.4.1" }
                context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("http://$host:8080/admin.html")))
            }) { Text("Translator controls") }
            OutlinedButton(onClick = {
                val host = ip.ifBlank { "192.168.4.1" }
                context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("http://$host:8080/listen.html")))
            }) { Text("Web test") }
        }
    }
}
