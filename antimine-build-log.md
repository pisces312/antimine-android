# antimine-android 构建记录

> 来源：GitHub lucasnlm/antimine-android  
> 分支：main，commit 2125次，版本 17.7.0  
> 目标：从源码编译 Debug 和 Release APK

---

## 一、环境准备

| 工具 | 版本 / 路径 |
|------|-------------|
| JDK | OpenJDK 21.0.10 — `D:\nili\dev\AndroidStudio\jbr` |
| Android SDK | 36.1.0 — `D:\nili\dev\android_sdk` |
| Gradle | 8.7（wrapper 内嵌） |
| Android Gradle Plugin | 8.5.0 |

确保已接受 SDK license：

```powershell
& "$env:ANDROID_HOME\cmdline-tools\latest\bin\sdkmanager.bat" --licenses
```

---

## 二、下载源码

```powershell
# 下载 ZIP（比 git clone 省空间，无历史）
Invoke-WebRequest "https://github.com/lucasnlm/antimine-android/archive/refs/heads/main.zip" -OutFile "$env:TEMP\antimine.zip"
Expand-Archive "$env:TEMP\antimine.zip" "D:\nili\3rd_party_projects\"
Move-Item "D:\nili\3rd_party_projects\antimine-android-main" "D:\nili\3rd_party_projects\antimine-android"
```

> ⚠️ 首次下载后若用 `Move-Item` 覆盖已有目录会导致目录丢失，重复下载即可恢复。

---

## 三、项目结构

```
antimine-android/
├── app/              主模块，应用入口，product flavors: google/googleInstant/auto/foss
├── ui/               UI 组件库（含 ThemedActivity）
├── tutorial/         新手教程模块
├── core/             游戏核心逻辑
├── common/           数据库、Room
├── preferences/      设置偏好
├── themes/           主题
├── external/         外部集成
├── gdx/              LibGDX 游戏引擎封装
├── sgtatham/         C++ 俄罗斯方块子模块（CMake 构建）
├── audio/            音效
├── about/            关于页
├── foss/             F-Droid 特定资源
├── donation/         捐赠
├── instant/          Google Instant App
├── proprietary/      Google 专有模块
├── auto/             汽车版
└── gradlew.bat       Gradle wrapper
```

---

## 四、Debug 构建

```powershell
Set-Location "D:\nili\3rd_party_projects\antimine-android"
& ".\gradlew.bat" --no-daemon assembleFossDebug
```

### 结果

| 项目 | 值 |
|------|---|
| APK | `app\build\outputs\apk\foss\debug\app-foss-debug.apk` |
| 大小 | 16.24 MB |
| 耗时 | ~3 分钟 |
| 状态 | ✅ 成功 |

> Debug 构建不需要签名，无混淆，直接成功。

---

## 五、Release 构建（遇到的问题）

### 5.1 首次尝试：开启 R8 混淆

```powershell
& ".\gradlew.bat" --no-daemon assembleFossRelease
```

**报错 1：R8 缺少类（tutorial 模块）**

```
* Missing class dev.lucasnlm.antimine.ui.ext.ThemedActivity
  (referenced by tutorial module)
```

原因：tutorial 依赖 ui 模块的类，但 R8 混淆时这些类被错误地丢弃。

**尝试修复：**

在 `app/proguard-rules.pro` 添加：

```proguard
-keep class dev.lucasnlm.antimine.ui.ext.ThemedActivity { *; }
-dontwarn dev.lucasnlm.antimine.ui.ext.ThemedActivity
```

重新构建 → 报错扩散，ui 模块还有更多缺失类：
- `ColorExt`、`SnackbarExt`、`AppSkin`、`AppTheme`、`AreaPalette`、
  `TopBarAction`、`ThemeRepository`、`ThemeRepositoryImpl` 等。

**报错 2：跨模块类名冲突**

```
Type a.a is defined multiple times
```

原因：R8 跨模块混淆时，tutorial 和 ui 模块中的类被压缩为相同短名，导致冲突。

### 5.2 解决思路

经过多次尝试，结论：**此项目的 R8 配置不完整**，需要维护大量跨模块依赖的 keep 规则，工程量大。

### 5.3 最终方案：关闭所有模块的混淆

| 模块 | 文件 | 修改内容 |
|------|------|----------|
| app | `app/build.gradle.kts` | `isMinifyEnabled = false` |
| ui | `ui/build.gradle.kts` | `isMinifyEnabled = false` |
| tutorial | `tutorial/build.gradle.kts` | 已经是 `false` |
| wear | `wear/build.gradle.kts` | `isMinifyEnabled = false` |

同时关闭 `isShrinkResources`（Android 要求：`isMinifyEnabled = false` 时 `isShrinkResources` 也必须为 false）。

**关键代码修改 - app/build.gradle.kts：**

```kotlin
getByName("release") {
    isMinifyEnabled = false
    isShrinkResources = false
    proguardFiles(
        getDefaultProguardFile("proguard-android-optimize.txt"),
        "proguard-rules.pro",
    )
    signingConfig = signingConfigs.getByName("release")
}
```

**同时修复签名配置 - app/build.gradle.kts：**

release signingConfig 原配置只在 CI 环境变量存在时填入 `storeFile`，本地构建缺少密钥导致失败。修改为：

```kotlin
signingConfigs {
    create("release") {
        val localKeystore = file("../foss-release.keystore")
        if (localKeystore.exists()) {
            storeFile = localKeystore
            keyAlias = "foss"
            storePassword = "foss123456"
            keyPassword = "foss123456"
        } else if (isReleaseBuild) {
            storeFile = file("../keystore")
            keyAlias = System.getenv("BITRISEIO_ANDROID_KEYSTORE_ALIAS")
            storePassword = System.getenv("BITRISEIO_ANDROID_KEYSTORE_PASSWORD")
            keyPassword = System.getenv("BITRISEIO_ANDROID_KEYSTORE_PRIVATE_KEY_PASSWORD")
        }
    }
}
```

本地生成测试签名：

```powershell
keytool -genkey -v -keystore "D:\nili\3rd_party_projects\antimine-android\foss-release.keystore" `
    -alias foss -keyalg RSA -keysize 2048 -validity 10000 `
    -storepass foss123456 -keypass foss123456 `
    -dname "CN=Test, OU=Test, O=Test, L=Test, ST=Test, C=CN"
```

### 5.4 最终构建命令

```powershell
Set-Location "D:\nili\3rd_party_projects\antimine-android"
& ".\gradlew.bat" --no-daemon clean assembleFossRelease
```

### 结果

| 项目 | 值 |
|------|---|
| APK | `app\build\outputs\apk\foss\release\app-foss-release.apk` |
| 大小 | 14.81 MB |
| 签名 | 测试密钥（alias: foss，keystore: foss-release.keystore） |
| 耗时 | ~2.5 分钟（干净构建） |
| 状态 | ✅ 成功 |

---

## 六、踩坑总结

| # | 问题 | 原因 | 解决 |
|---|------|------|------|
| 1 | R8 报 Missing class `ThemedActivity` | R8 混淆 ui 模块时丢弃了被其他模块引用的 public 类 | 关闭 app/ui/wear 的 minifyEnabled |
| 2 | 类名冲突 `Type a.a is defined multiple times` | 跨模块 R8 混淆时多个模块的类被压缩为相同短名 | 同上 |
| 3 | `isShrinkResources requires unused code shrinking` | minify=false 时不能开 shrinkResources | 同时关闭 shrinkResources |
| 4 | `SigningConfig "release" is missing required property "storeFile"` | release signingConfig 只在 CI 环境变量存在时才设 storeFile | 修改 build.gradle.kts，本地存在 keystore 时使用本地配置 |

---

## 七、最终产物

```
D:\nili\3rd_party_projects\antimine-android\
├── app-foss-release-unsigned.apk       # 重命名后的 Release APK（14.81 MB）
├── foss-release.keystore               # 测试签名密钥（勿用于正式发布）
└── app/build/outputs/apk/foss/release/
    └── app-foss-release.apk            # Release APK（原始路径）
```

> ⚠️ **正式发布需替换签名密钥**：当前使用的是自签名测试密钥，不能发布到应用商店。