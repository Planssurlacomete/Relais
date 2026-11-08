#!/usr/bin/env python3
"""Generate a dependency-free, traditional Xcode project from current Swift files.
Run again after adding/removing Swift sources or bundled resource files.
"""
from pathlib import Path
import hashlib
import json

root = Path(__file__).resolve().parents[1]
project = root / "Relais.xcodeproj"
project.mkdir(exist_ok=True)

def ident(name):
    return hashlib.sha1(name.encode()).hexdigest()[:24].upper()

def q(value):
    return json.dumps(str(value), ensure_ascii=False)

ids = {name: ident(name) for name in ["project", "target", "main", "sources", "resources", "products", "app", "info", "entitlements", "sourcePhase", "resourcePhase", "frameworkPhase", "projectConfigList", "targetConfigList"]}
sources = sorted((root / "Relais").rglob("*.swift"))
resources = sorted(p for p in (root / "Relais" / "Resources").rglob("*") if p.is_file() and not p.name.startswith("."))
lines = ["// !$*UTF8*$!", "{", "\tarchiveVersion = 1;", "\tclasses = {};", "\tobjectVersion = 56;", "\tobjects = {"]
def obj(key, body):
    lines.append(f"\t\t{key} = {{ {body} }};")

source_ids = []
resource_ids = []
source_builds = []
resource_builds = []
for file, group, builds in [(p, source_ids, source_builds) for p in sources] + [(p, resource_ids, resource_builds) for p in resources]:
    relative = file.relative_to(root).as_posix()
    fid = ident("file:" + relative)
    bid = ident("build:" + relative)
    typ = "sourcecode.swift" if file.suffix == ".swift" else ("image.icns" if file.suffix == ".icns" else ("text.plist.xml" if file.suffix == ".plist" else "text"))
    obj(fid, f"isa = PBXFileReference; lastKnownFileType = {typ}; name = {q(file.name)}; path = {q(relative)}; sourceTree = SOURCE_ROOT;")
    obj(bid, f"isa = PBXBuildFile; fileRef = {fid};")
    group.append(fid)
    builds.append(bid)
obj(ids["app"], 'isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Relais.app; sourceTree = BUILT_PRODUCTS_DIR;')
obj(ids["info"], 'isa = PBXFileReference; lastKnownFileType = text.plist.xml; name = Info.plist; path = Relais/Info.plist; sourceTree = SOURCE_ROOT;')
obj(ids["entitlements"], 'isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; name = Relais.entitlements; path = Relais/Relais.entitlements; sourceTree = SOURCE_ROOT;')
def arr(values): return "(" + ", ".join(values) + ")"
obj(ids["sources"], f'isa = PBXGroup; children = {arr(source_ids)}; name = Sources; sourceTree = "<group>";')
obj(ids["resources"], f'isa = PBXGroup; children = {arr(resource_ids + [ids["info"], ids["entitlements"]])}; name = Resources; sourceTree = "<group>";')
obj(ids["products"], f'isa = PBXGroup; children = ({ids["app"]}); name = Products; sourceTree = "<group>";')
obj(ids["main"], f'isa = PBXGroup; children = {arr([ids["sources"], ids["resources"], ids["products"]])}; sourceTree = "<group>";')
for name, kind, builds in [("sourcePhase", "PBXSourcesBuildPhase", source_builds), ("resourcePhase", "PBXResourcesBuildPhase", resource_builds), ("frameworkPhase", "PBXFrameworksBuildPhase", [])]:
    obj(ids[name], f"isa = {kind}; buildActionMask = 2147483647; files = {arr(builds)}; runOnlyForDeploymentPostprocessing = 0;")
obj(ids["target"], f'isa = PBXNativeTarget; buildConfigurationList = {ids["targetConfigList"]}; buildPhases = {arr([ids["sourcePhase"], ids["frameworkPhase"], ids["resourcePhase"]])}; buildRules = (); dependencies = (); name = Relais; productName = Relais; productReference = {ids["app"]}; productType = "com.apple.product-type.application";')
obj(ids["project"], f'isa = PBXProject; attributes = {{ BuildIndependentTargetsInParallel = YES; LastSwiftUpdateCheck = 1600; LastUpgradeCheck = 1600; }}; buildConfigurationList = {ids["projectConfigList"]}; compatibilityVersion = "Xcode 14.0"; developmentRegion = fr; hasScannedForEncodings = 0; knownRegions = (fr, en, Base); mainGroup = {ids["main"]}; productRefGroup = {ids["products"]}; projectDirPath = ""; projectRoot = ""; targets = ({ids["target"]});')
for level in ["project", "target"]:
    configs = []
    for name in ["Debug", "Release"]:
        cid = ident(level + name)
        configs.append(cid)
        if level == "project":
            settings = {
                "SDKROOT": "macosx", "MACOSX_DEPLOYMENT_TARGET": "14.0", "ARCHS": "arm64",
                "CLANG_ENABLE_MODULES": "YES", "SWIFT_VERSION": "5.0", "GCC_C_LANGUAGE_STANDARD": "gnu17",
                "SWIFT_OPTIMIZATION_LEVEL": "-Onone" if name == "Debug" else "-O",
                "DEBUG_INFORMATION_FORMAT": "dwarf" if name == "Debug" else "dwarf-with-dsym",
                "SWIFT_COMPILATION_MODE": "singlefile" if name == "Debug" else "wholemodule",
                "ENABLE_HARDENED_RUNTIME": "YES", "ONLY_ACTIVE_ARCH": "YES" if name == "Debug" else "NO",
            }
        else:
            settings = {
                "PRODUCT_BUNDLE_IDENTIFIER": "org.relaisapp.Relais", "PRODUCT_NAME": "Relais",
                "INFOPLIST_FILE": "Relais/Info.plist", "GENERATE_INFOPLIST_FILE": "NO",
                "MARKETING_VERSION": "1.0.2", "CURRENT_PROJECT_VERSION": "5",
                "CODE_SIGN_IDENTITY": "-", "CODE_SIGN_STYLE": "Manual", "DEVELOPMENT_TEAM": "",
                "CODE_SIGN_ENTITLEMENTS": "Relais/Relais.entitlements", "ENABLE_HARDENED_RUNTIME": "YES",
                "COMBINE_HIDPI_IMAGES": "YES", "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/../Frameworks",
                "SWIFT_EMIT_LOC_STRINGS": "NO", "ENABLE_APP_SANDBOX": "YES", "SUPPORTED_PLATFORMS": "macosx",
            }
        text = " ".join(f"{key} = {q(value)};" for key, value in settings.items())
        obj(cid, f"isa = XCBuildConfiguration; buildSettings = {{ {text} }}; name = {name};")
    obj(ids[level + "ConfigList"], f"isa = XCConfigurationList; buildConfigurations = {arr(configs)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;")
lines.extend(["\t};", f"\trootObject = {ids['project']};", "}"])
(project / "project.pbxproj").write_text("\n".join(lines) + "\n")
scheme_dir = project / "xcshareddata" / "xcschemes"
scheme_dir.mkdir(parents=True, exist_ok=True)
ref = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ids["target"]}" BuildableName="Relais.app" BlueprintName="Relais" ReferencedContainer="container:Relais.xcodeproj"/>'
scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{ref}</BuildActionEntry></BuildActionEntries></BuildAction>
  <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"/>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="NO"><BuildableProductRunnable runnableDebuggingMode="0">{ref}</BuildableProductRunnable></LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref}</BuildableProductRunnable></ProfileAction>
  <AnalyzeAction buildConfiguration="Debug"/>
  <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
'''
(scheme_dir / "Relais.xcscheme").write_text(scheme)
print(f"Generated Xcode project: {len(sources)} Swift files, {len(resources)} resources")
