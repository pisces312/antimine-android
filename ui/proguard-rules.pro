-dontwarn java.lang.invoke.StringConcatFactory
-dontwarn com.google.android.material.R$attr
-dontwarn dev.lucasnlm.antimine.i18n.R$string
-dontwarn dev.lucasnlm.antimine.ui.ext.ThemedActivity

# Keep UI API classes for consumer modules
-keep class dev.lucasnlm.antimine.ui.ext.ThemedActivity { *; }