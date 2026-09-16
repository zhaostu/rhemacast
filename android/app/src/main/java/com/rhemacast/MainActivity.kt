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
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Button
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Slider
import androidx.compose.material3.TextButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
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

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ListenerScreen() {
    val context = LocalContext.current
    val audio = remember {
        context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    }
    var ip by remember { mutableStateOf("192.168.4.1") }
    val status by PlaybackService.status.collectAsState()
    val stats by PlaybackService.stats.collectAsState()
    // Voice-call stream matches MODE_IN_COMMUNICATION routing (headphones).
    val volStream = AudioManager.STREAM_VOICE_CALL
    val maxVol = remember { audio.getStreamMaxVolume(volStream) }
    var volume by remember {
        mutableFloatStateOf(audio.getStreamVolume(volStream).toFloat())
    }
    var settingsExpanded by remember { mutableStateOf(false) }
    val playing = status.startsWith("Playing") || status.startsWith("Connecting")
    var outputMenuOpen by remember { mutableStateOf(false) }
    val outputs = AudioRouter.available(audio)
    var selected by remember { mutableStateOf(AudioRouter.selected) }

    Column(
        Modifier.fillMaxSize().padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text("Rhemacast Listener", style = MaterialTheme.typography.headlineSmall)
        Text("Status: $status", style = MaterialTheme.typography.bodyLarge)
        if (stats.isNotEmpty()) Text(stats, style = MaterialTheme.typography.bodyMedium)

        // Big central on/off toggle.
        Box(
            Modifier.weight(1f).fillMaxWidth(),
            contentAlignment = Alignment.Center,
        ) {
            Button(
                onClick = {
                    if (playing) {
                        PlaybackService.stop(context)
                    } else {
                        PlaybackService.start(context, ip)
                    }
                },
                enabled = playing || ip.isNotBlank(),
                shape = CircleShape,
                colors = ButtonDefaults.buttonColors(
                    containerColor = if (playing) MaterialTheme.colorScheme.error
                    else MaterialTheme.colorScheme.primary,
                ),
                modifier = Modifier.size(200.dp),
            ) {
                Text(
                    if (playing) "Stop" else "Listen",
                    fontSize = 28.sp,
                )
            }
        }

        // Compact output picker (stays on screen, small).
        Row(
            Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text("Output", style = MaterialTheme.typography.bodySmall)
            Box {
                TextButton(
                    onClick = { outputMenuOpen = true },
                    contentPadding = PaddingValues(horizontal = 4.dp, vertical = 0.dp),
                ) {
                    Text(selected.label, style = MaterialTheme.typography.bodySmall)
                }
                DropdownMenu(
                    expanded = outputMenuOpen,
                    onDismissRequest = { outputMenuOpen = false },
                ) {
                    for (o in outputs) {
                        DropdownMenuItem(
                            text = { Text(o.label, style = MaterialTheme.typography.bodySmall) },
                            onClick = {
                                outputMenuOpen = false
                                selected = o
                                AudioRouter.selected = o
                                AudioRouter.apply(audio, o)
                                // Refresh voice-call volume after route change.
                                volume = audio.getStreamVolume(volStream).toFloat()
                            },
                        )
                    }
                }
            }
        }

        Text("Volume")
        Slider(
            value = volume,
            onValueChange = {
                volume = it
                audio.setStreamVolume(volStream, it.toInt(), 0)
            },
            valueRange = 0f..maxVol.toFloat(),
            steps = maxVol - 1,
            modifier = Modifier.fillMaxWidth(),
        )

        // Non-essential settings live in a popup so the big button never moves.
        OutlinedButton(
            onClick = { settingsExpanded = true },
            modifier = Modifier.fillMaxWidth(),
        ) {
            Text("Settings")
        }
        if (settingsExpanded) {
            ModalBottomSheet(
                onDismissRequest = { settingsExpanded = false },
            ) {
                Column(
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp),
                ) {
                    Text("Settings", style = MaterialTheme.typography.titleMedium)
                    OutlinedTextField(
                        value = ip,
                        onValueChange = { ip = it.trim() },
                        label = { Text("Server IP") },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth(),
                    )
                    Text("WHEP: http://$ip:8080/whep", style = MaterialTheme.typography.bodySmall)
                    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        OutlinedButton(onClick = {
                            val host = ip.ifBlank { "192.168.4.1" }
                            context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("http://$host:8080/admin.html")))
                        }) { Text("Broadcast controls") }
                        OutlinedButton(onClick = {
                            val host = ip.ifBlank { "192.168.4.1" }
                            context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("http://$host:8080/listen.html")))
                        }) { Text("Web test") }
                    }
                    Spacer(Modifier.height(16.dp))
                }
            }
        }
    }
}
