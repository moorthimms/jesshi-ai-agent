"""Generate a dependency-free Xcode project using only Apple frameworks."""
from pathlib import Path
root=Path(__file__).parent
files=['Jessy/JessyApp.swift','../shared/PortableBackup.swift','../shared/DeviceServices.swift','../shared/Retrieval.swift']
def uid(n):return f'{n:024X}'
objects=[f'{uid(300)} = {{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Jessy/Assets.xcassets; sourceTree = SOURCE_ROOT; }};', f'{uid(301)} = {{isa = PBXBuildFile; fileRef = {uid(300)}; }};']
for i,f in enumerate(files):
 objects += [f'{uid(100+i)} = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "{f}"; sourceTree = SOURCE_ROOT; }};',f'{uid(200+i)} = {{isa = PBXBuildFile; fileRef = {uid(100+i)}; }};']
objects += [f'{uid(1)} = {{isa = PBXProject; attributes = {{LastUpgradeCheck = 2600; }}; buildConfigurationList = {uid(10)}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; knownRegions = (en, Base); mainGroup = {uid(2)}; productRefGroup = {uid(3)}; projectDirPath = ""; projectRoot = ""; targets = ({uid(4)}); }};',
f'{uid(2)} = {{isa = PBXGroup; children = ({",".join(uid(100+i) for i in range(len(files)))},{uid(3)},{uid(300)}); sourceTree = "<group>"; }};',
f'{uid(3)} = {{isa = PBXGroup; children = ({uid(5)}); name = Products; sourceTree = "<group>"; }};',
f'{uid(5)} = {{isa = PBXFileReference; explicitFileType = wrapper.application; path = Jessy.app; sourceTree = BUILT_PRODUCTS_DIR; }};',
f'{uid(4)} = {{isa = PBXNativeTarget; buildConfigurationList = {uid(11)}; buildPhases = ({uid(6)},{uid(7)},{uid(8)}); buildRules = (); dependencies = (); name = Jessy; productName = Jessy; productReference = {uid(5)}; productType = "com.apple.product-type.application"; }};',
f'{uid(6)} = {{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({",".join(uid(200+i) for i in range(len(files)))}); runOnlyForDeploymentPostprocessing = 0; }};',
f'{uid(7)} = {{isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; }};',
f'{uid(8)} = {{isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({uid(301)}); runOnlyForDeploymentPostprocessing = 0; }};']
for cfg,name in [(20,'Debug'),(21,'Release')]:
 objects.append(f'{uid(cfg)} = {{isa = XCBuildConfiguration; buildSettings = {{SDKROOT = iphoneos; IPHONEOS_DEPLOYMENT_TARGET = 26.0; SWIFT_VERSION = 5.0; CLANG_ENABLE_MODULES = YES; }}; name = {name}; }};')
 opt = '-Onone' if name == 'Debug' else '-O'
 objects.append(f'{uid(cfg+2)} = {{isa = XCBuildConfiguration; buildSettings = {{PRODUCT_BUNDLE_IDENTIFIER = local.jessy.assistant; PRODUCT_NAME = Jessy; INFOPLIST_FILE = Jessy/Info.plist; CODE_SIGN_STYLE = Automatic; TARGETED_DEVICE_FAMILY = "1,2"; SWIFT_VERSION = 5.0; IPHONEOS_DEPLOYMENT_TARGET = 26.0; GENERATE_INFOPLIST_FILE = NO; ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon; SWIFT_OPTIMIZATION_LEVEL = "{opt}"; }}; name = {name}; }};')
for n,a,b in [(10,20,21),(11,22,23)]:objects.append(f'{uid(n)} = {{isa = XCConfigurationList; buildConfigurations = ({uid(a)},{uid(b)}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }};')
(root/'Jessy.xcodeproj/project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'+'\n'.join(objects)+f'\n}}; rootObject = {uid(1)}; }}\n')
