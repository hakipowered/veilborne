package com.veilborne;

import android.app.Activity;
import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.UsedByGodot;
import org.godotengine.godot.utils.ProcessPhoenix;

/**
 * Lets the game restart itself after it installed a content pack.
 * GDScript: Engine.get_singleton("VeilRestart").restart()
 * Uses Godot's own ProcessPhoenix (already in the APK), which kills this
 * process and launches the game again from a helper process.
 */
public class VeilRestart extends GodotPlugin {
	public VeilRestart(Godot godot) {
		super(godot);
	}

	@Override
	public String getPluginName() {
		return "VeilRestart";
	}

	@UsedByGodot
	public void restart() {
		final Activity activity = getActivity();
		if (activity == null) {
			return;
		}
		activity.runOnUiThread(new Runnable() {
			@Override
			public void run() {
				ProcessPhoenix.triggerRebirth(activity);
			}
		});
	}
}
