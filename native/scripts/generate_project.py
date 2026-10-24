#!/usr/bin/env python3
"""Dependency-free deterministic Xcode project generator. Run after editing project settings."""
import hashlib
import json
import os
import pathlib
import plistlib
import xml.etree.ElementTree as ET
ROOT = pathlib.Path(__file__).resolve().parents[1]
objects = {}
def ident(name): return hashlib.sha256(name.encode()).hexdigest()[:24].upper()
def obj(key, isa, **fields):
    key = ident(key); objects[key] = dict(isa=isa, **fields); return key
def dump(value, indent=0):
    if isinstance(value, dict):
        return '{\n' + ''.join('\t'*(indent+1)+f'{json.dumps(k)} = {dump(v,indent+1)};\n' for k,v in value.items()) + '\t'*indent+'}'
    if isinstance(value, list): return '(\n'+''.join('\t'*(indent+1)+dump(v,indent+1)+',\n' for v in value)+'\t'*indent+')'
    return json.dumps(str(value))
def configs(key, settings):
    ids=[]
    for name in ['Debug', 'Release']:
        bs=dict(settings)
        if name=='Debug': bs.update(SWIFT_OPTIMIZATION_LEVEL='-Onone', DEBUG_INFORMATION_FORMAT='dwarf', SWIFT_ACTIVE_COMPILATION_CONDITIONS='DEBUG', ONLY_ACTIVE_ARCH='YES')
        else: bs.update(SWIFT_OPTIMIZATION_LEVEL='-O', DEBUG_INFORMATION_FORMAT='dwarf-with-dsym')
        ids.append(obj(f'{key}-{name}','XCBuildConfiguration',name=name,buildSettings=bs))
    return obj(f'{key}-configs','XCConfigurationList',buildConfigurations=ids,defaultConfigurationIsVisible=0,defaultConfigurationName='Release')
source=obj('source','PBXFileReference',lastKnownFileType='sourcecode.swift',path='App/RelayApp.swift',sourceTree='<group>')
extraSources=[obj('extra-'+name,'PBXFileReference',lastKnownFileType='sourcecode.swift',path='App/'+name+'.swift',sourceTree='<group>') for name in ['CloudAuth','CloudModel','CloudViews','VoiceRecorder','RequestLocationModel','WorkflowViews','WorkflowStyle','LiveSpeechRecorder','AnnouncementViews','ResidentDetailsVault','ResidentViews','IdentityViews']]
shelterSource=obj('shelter-source','PBXFileReference',lastKnownFileType='sourcecode.swift',path='App/ShelterViews.swift',sourceTree='<group>')
assets=obj('assets','PBXFileReference',lastKnownFileType='folder.assetcatalog',path='App/Assets.xcassets',sourceTree='<group>')
package=obj('package','XCLocalSwiftPackageReference',relativePath='.')
products=[]; targets=[]
for platform in ['iOS','macOS']:
    name=f'RELAY-{platform}'
    product=obj(name+'-app','PBXFileReference',explicitFileType='wrapper.application',includeInIndex=0,path=name+'.app',sourceTree='BUILT_PRODUCTS_DIR'); products.append(product)
    dep=obj(name+'-dependency','XCSwiftPackageProductDependency',package=package,productName='RelayCore')
    sourceBuild=obj(name+'-source','PBXBuildFile',fileRef=source)
    shelterBuild=obj(name+'-shelter-source','PBXBuildFile',fileRef=shelterSource)
    libBuild=obj(name+'-lib','PBXBuildFile',productRef=dep)
    srcPhase=obj(name+'-sources','PBXSourcesBuildPhase',buildActionMask=2147483647,files=[sourceBuild,shelterBuild]+[obj(name+'-extra-'+str(i),'PBXBuildFile',fileRef=ref) for i,ref in enumerate(extraSources)],runOnlyForDeploymentPostprocessing=0)
    libPhase=obj(name+'-frameworks','PBXFrameworksBuildPhase',buildActionMask=2147483647,files=[libBuild],runOnlyForDeploymentPostprocessing=0)
    assetBuild=obj(name+'-assets','PBXBuildFile',fileRef=assets)
    resPhase=obj(name+'-resources','PBXResourcesBuildPhase',buildActionMask=2147483647,files=[assetBuild],runOnlyForDeploymentPostprocessing=0)
    settings=dict(PRODUCT_NAME='$(TARGET_NAME)', PRODUCT_BUNDLE_IDENTIFIER=f'org.relay.prototype.{platform.lower()}',
                  INFOPLIST_FILE=f'Config/{platform}-Info.plist',GENERATE_INFOPLIST_FILE='NO',SWIFT_VERSION='5.0',
                  CODE_SIGN_STYLE='Automatic',DEVELOPMENT_TEAM='',CURRENT_PROJECT_VERSION=23,MARKETING_VERSION='0.1.0',
                  LD_RUNPATH_SEARCH_PATHS='$(inherited) @executable_path/Frameworks', ASSETCATALOG_COMPILER_APPICON_NAME='AppIcon')
    if platform=='iOS': settings.update(PRODUCT_BUNDLE_IDENTIFIER='com.nikilthalapaneni.relay',DEVELOPMENT_TEAM='U4G9LV39GM',SDKROOT='iphoneos',SUPPORTED_PLATFORMS='iphoneos iphonesimulator',IPHONEOS_DEPLOYMENT_TARGET='17.0',TARGETED_DEVICE_FAMILY='1,2',SUPPORTS_MACCATALYST='NO')
    else: settings.update(SDKROOT='macosx',SUPPORTED_PLATFORMS='macosx',MACOSX_DEPLOYMENT_TARGET='14.0',CODE_SIGN_IDENTITY='-',CODE_SIGN_ENTITLEMENTS='Config/macOS.entitlements',ENABLE_HARDENED_RUNTIME='YES',LD_RUNPATH_SEARCH_PATHS='$(inherited) @executable_path/../Frameworks')
    target=obj(name,'PBXNativeTarget',name=name,productName=name,productReference=product,productType='com.apple.product-type.application',
               buildConfigurationList=configs(name,settings),buildPhases=[srcPhase,libPhase,resPhase],buildRules=[],dependencies=[],packageProductDependencies=[dep]); targets.append(target)
    scheme=ET.Element('Scheme',LastUpgradeVersion='2610',version='1.3')
    action=ET.SubElement(scheme,'BuildAction',parallelizeBuildables='YES',buildImplicitDependencies='YES')
    entries=ET.SubElement(action,'BuildActionEntries')
    entry=ET.SubElement(entries,'BuildActionEntry',buildForTesting='YES',buildForRunning='YES',buildForProfiling='YES',buildForArchiving='YES',buildForAnalyzing='YES')
    def ref(parent): ET.SubElement(parent,'BuildableReference',BuildableIdentifier='primary',BlueprintIdentifier=target,BuildableName=name+'.app',BlueprintName=name,ReferencedContainer='container:RELAY.xcodeproj')
    ref(entry)
    launch=ET.SubElement(scheme,'LaunchAction',buildConfiguration='Debug',selectedDebuggerIdentifier='Xcode.DebuggerFoundation.Debugger.LLDB',selectedLauncherIdentifier='Xcode.IDEFoundation.Launcher.LLDB',launchStyle='0',useCustomWorkingDirectory='NO',ignoresPersistentStateOnLaunch='NO',debugDocumentVersioning='YES',debugServiceExtension='internal',allowLocationSimulation='YES')
    ref(ET.SubElement(launch,'BuildableProductRunnable',runnableDebuggingMode='0'))
    ET.SubElement(scheme,'AnalyzeAction',buildConfiguration='Debug'); ET.SubElement(scheme,'ArchiveAction',buildConfiguration='Release',revealArchiveInOrganizer='YES')
    out=ROOT/'RELAY.xcodeproj/xcshareddata/xcschemes'/f'{name}.xcscheme'; out.parent.mkdir(parents=True,exist_ok=True)
    ET.indent(scheme); ET.ElementTree(scheme).write(out,encoding='UTF-8',xml_declaration=True)
productGroup=obj('products','PBXGroup',children=products,name='Products',sourceTree='<group>')
main=obj('main','PBXGroup',children=[source,shelterSource,assets,productGroup]+extraSources,sourceTree='<group>')
project=obj('project','PBXProject',attributes=dict(BuildIndependentTargetsInParallel='YES',LastUpgradeCheck=2610),buildConfigurationList=configs('project',dict(CLANG_ENABLE_MODULES='YES',SWIFT_VERSION='5.0',SWIFT_STRICT_CONCURRENCY='minimal')),compatibilityVersion='Xcode 14.0',developmentRegion='en',hasScannedForEncodings=0,knownRegions=['en','Base'],mainGroup=main,productRefGroup=productGroup,projectDirPath='',projectRoot='',targets=targets,packageReferences=[package])
(ROOT/'RELAY.xcodeproj/project.pbxproj').write_text('// !$*UTF8*$!\n'+dump(dict(archiveVersion=1,classes={},objectVersion=56,objects=objects,rootObject=project))+'\n')
for platform in ['iOS','macOS']:
    info=dict(RELAYCloudAPIURL=os.environ.get('RELAY_CLOUD_API_URL',''),CFBundleDevelopmentRegion='en',CFBundleDisplayName='RELAY',CFBundleExecutable='$(EXECUTABLE_NAME)',CFBundleIdentifier='$(PRODUCT_BUNDLE_IDENTIFIER)',CFBundleInfoDictionaryVersion='6.0',CFBundleName='$(PRODUCT_NAME)',CFBundlePackageType='APPL',CFBundleShortVersionString='$(MARKETING_VERSION)',CFBundleVersion='$(CURRENT_PROJECT_VERSION)',NSLocalNetworkUsageDescription='RELAY discovers nearby Apple devices and carries synthetic messages between them without a server.',NSBonjourServices=['_relay-poc._tcp'],NSLocationWhenInUseUsageDescription='Attach your current location to a help request so authorized shelter staff can find you.',NSLocationUsageDescription='Attach a location snapshot to your request.',NSMicrophoneUsageDescription='Record a short request, then review its cloud transcript before sending.',CFBundleURLTypes=[{'CFBundleURLName':'RELAY Sign In','CFBundleURLSchemes':['relay']}])
    if platform=='iOS': info.update(ITSAppUsesNonExemptEncryption=False,UILaunchScreen={},UIApplicationSceneManifest={'UIApplicationSupportsMultipleScenes':False},UISupportedInterfaceOrientations=['UIInterfaceOrientationPortrait','UIInterfaceOrientationPortraitUpsideDown','UIInterfaceOrientationLandscapeLeft','UIInterfaceOrientationLandscapeRight'])
    else: info.update(LSMinimumSystemVersion='$(MACOSX_DEPLOYMENT_TARGET)',NSHighResolutionCapable=True,NSPrincipalClass='NSApplication')
    with (ROOT/f'Config/{platform}-Info.plist').open('wb') as f: plistlib.dump(info,f)
with (ROOT/'Config/macOS.entitlements').open('wb') as f:
    plistlib.dump({'com.apple.security.app-sandbox':True,'com.apple.security.network.client':True,'com.apple.security.network.server':True,'com.apple.security.device.audio-input':True,'com.apple.security.files.user-selected.read-only':True,'com.apple.security.personal-information.location':True},f)
print('Generated RELAY.xcodeproj (iOS + macOS, local RelayCore package; no downloads)')
