package org.godotengine.godot.plugin;
public abstract class GodotPlugin {
	public GodotPlugin(org.godotengine.godot.Godot godot) {}
	protected android.app.Activity getActivity() { return null; }
	public abstract String getPluginName();
}
