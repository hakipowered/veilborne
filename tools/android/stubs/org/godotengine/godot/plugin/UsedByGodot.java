package org.godotengine.godot.plugin;
import java.lang.annotation.*;
@Target({ ElementType.METHOD })
@Retention(RetentionPolicy.RUNTIME)
public @interface UsedByGodot {}
