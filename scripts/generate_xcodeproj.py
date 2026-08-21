#!/usr/bin/env python3
"""Generates OffRentLedger.xcodeproj/project.pbxproj.

A pbxproj is a hand-maintainable format right up until it is not, and this one was authored on a
machine with no Xcode to validate it. Generating it from a script rather than editing it by hand
means the object graph is internally consistent by construction: every ID referenced is an ID
defined, every target has exactly the phases it needs, and adding a target is a change in one
place instead of eleven.

The project uses Xcode 16 file-system-synchronized groups (`PBXFileSystemSynchronizedRootGroup`),
so source files are never individually listed. Adding a .swift file to a synchronized folder puts
it in the target with no project edit at all — which is also why a merge conflict in this file is
almost impossible.

Run:  python3 scripts/generate_xcodeproj.py
Check: python3 scripts/generate_xcodeproj.py --check   (fails if the committed file is stale)
"""

import sys, pathlib, difflib

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "OffRentLedger.xcodeproj" / "project.pbxproj"


def oid(n: int) -> str:
    """24 uppercase hex characters, the shape Xcode writes."""
    return "0FF" + format(n, "021X")


# --- object identifiers -------------------------------------------------------------------
PROJECT          = oid(0x01)
MAIN_GROUP       = oid(0x02)
PRODUCTS_GROUP   = oid(0x03)
CONFIG_GROUP     = oid(0x04)
STOREKIT_GROUP   = oid(0x05)

T_APP            = oid(0x10)
T_TESTS          = oid(0x11)
T_UITESTS        = oid(0x12)
T_WIDGET         = oid(0x13)

P_APP            = oid(0x20)
P_TESTS          = oid(0x21)
P_UITESTS        = oid(0x22)
P_WIDGET         = oid(0x23)

FSG_APP          = oid(0x30)
FSG_SHARED       = oid(0x31)
FSG_TESTS        = oid(0x32)
FSG_UITESTS      = oid(0x33)
FSG_WIDGET       = oid(0x34)

F_XCCONFIG       = oid(0x40)
F_APP_PLIST      = oid(0x41)
F_WIDGET_PLIST   = oid(0x42)
F_APP_ENTS       = oid(0x43)
F_WIDGET_ENTS    = oid(0x44)
F_STOREKIT       = oid(0x45)

BF_WIDGET_EMBED  = oid(0x50)
PHASE_EMBED      = oid(0x51)

SOURCES          = {T_APP: oid(0x60), T_TESTS: oid(0x61), T_UITESTS: oid(0x62), T_WIDGET: oid(0x63)}
FRAMEWORKS       = {T_APP: oid(0x64), T_TESTS: oid(0x65), T_UITESTS: oid(0x66), T_WIDGET: oid(0x67)}
RESOURCES        = {T_APP: oid(0x68), T_TESTS: oid(0x69), T_UITESTS: oid(0x6A), T_WIDGET: oid(0x6B)}

CL_PROJECT       = oid(0x70)
CL               = {T_APP: oid(0x71), T_TESTS: oid(0x72), T_UITESTS: oid(0x73), T_WIDGET: oid(0x74)}

BC_PROJECT       = {"Debug": oid(0x80), "Release": oid(0x81)}
BC               = {
    T_APP:     {"Debug": oid(0x82), "Release": oid(0x83)},
    T_TESTS:   {"Debug": oid(0x84), "Release": oid(0x85)},
    T_UITESTS: {"Debug": oid(0x86), "Release": oid(0x87)},
    T_WIDGET:  {"Debug": oid(0x88), "Release": oid(0x89)},
}

DEP_TESTS        = oid(0x90)
DEP_UITESTS      = oid(0x91)
DEP_WIDGET       = oid(0x92)
PROXY_TESTS      = oid(0x93)
PROXY_UITESTS    = oid(0x94)
PROXY_WIDGET     = oid(0x95)


def settings(pairs, indent=4):
    """Renders a build-settings dict, quoting only what needs it."""
    pad = "\t" * indent
    out = []
    for key, value in pairs:
        if isinstance(value, list):
            out.append(f"{pad}{key} = (")
            for entry in value:
                out.append(f'{pad}\t"{entry}",')
            out.append(f"{pad});")
        else:
            text = str(value)
            needs_quotes = (
                text == ""
                or any(c in text for c in ' ,;()"$@/\\<>&\'!?:.-')
            )
            # Plain identifiers and simple numbers go unquoted, as Xcode writes them.
            if text.replace("_", "").replace(".", "").isalnum() and " " not in text and "$" not in text:
                needs_quotes = False if text.replace("_", "").isalnum() else needs_quotes
            if needs_quotes:
                text = '"' + text.replace('\\', '\\\\').replace('"', '\\"') + '"'
            out.append(f"{pad}{key} = {text};")
    return "\n".join(out)


# --- shared build settings ----------------------------------------------------------------

COMMON_WARNINGS = [
    ("ALWAYS_SEARCH_USER_PATHS", "NO"),
    ("ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS", "YES"),
    ("CLANG_ANALYZER_NONNULL", "YES"),
    ("CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION", "YES_AGGRESSIVE"),
    ("CLANG_ENABLE_MODULES", "YES"),
    ("CLANG_ENABLE_OBJC_ARC", "YES"),
    ("CLANG_ENABLE_OBJC_WEAK", "YES"),
    ("CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING", "YES"),
    ("CLANG_WARN_BOOL_CONVERSION", "YES"),
    ("CLANG_WARN_COMMA", "YES"),
    ("CLANG_WARN_CONSTANT_CONVERSION", "YES"),
    ("CLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS", "YES"),
    ("CLANG_WARN_DIRECT_OBJC_ISA_USAGE", "YES_ERROR"),
    ("CLANG_WARN_DOCUMENTATION_COMMENTS", "YES"),
    ("CLANG_WARN_EMPTY_BODY", "YES"),
    ("CLANG_WARN_ENUM_CONVERSION", "YES"),
    ("CLANG_WARN_INFINITE_RECURSION", "YES"),
    ("CLANG_WARN_INT_CONVERSION", "YES"),
    ("CLANG_WARN_NON_LITERAL_NULL_CONVERSION", "YES"),
    ("CLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF", "YES"),
    ("CLANG_WARN_OBJC_LITERAL_CONVERSION", "YES"),
    ("CLANG_WARN_OBJC_ROOT_CLASS", "YES_ERROR"),
    ("CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER", "YES"),
    ("CLANG_WARN_RANGE_LOOP_ANALYSIS", "YES"),
    ("CLANG_WARN_STRICT_PROTOTYPES", "YES"),
    ("CLANG_WARN_SUSPICIOUS_MOVE", "YES"),
    ("CLANG_WARN_UNGUARDED_AVAILABILITY", "YES_AGGRESSIVE"),
    ("CLANG_WARN_UNREACHABLE_CODE", "YES"),
    ("CLANG_WARN__DUPLICATE_METHOD_MATCH", "YES"),
    ("COPY_PHASE_STRIP", "NO"),
    ("ENABLE_STRICT_OBJC_MSGSEND", "YES"),
    ("ENABLE_USER_SCRIPT_SANDBOXING", "YES"),
    ("GCC_C_LANGUAGE_STANDARD", "gnu17"),
    ("GCC_NO_COMMON_BLOCKS", "YES"),
    ("GCC_WARN_64_TO_32_BIT_CONVERSION", "YES"),
    ("GCC_WARN_ABOUT_RETURN_TYPE", "YES_ERROR"),
    ("GCC_WARN_UNDECLARED_SELECTOR", "YES"),
    ("GCC_WARN_UNINITIALIZED_AUTOS", "YES_AGGRESSIVE"),
    ("GCC_WARN_UNUSED_FUNCTION", "YES"),
    ("GCC_WARN_UNUSED_VARIABLE", "YES"),
    ("CURRENT_PROJECT_VERSION", "$(OFFRENT_BUILD_NUMBER)"),
    ("MARKETING_VERSION", "$(OFFRENT_MARKETING_VERSION)"),
    ("IPHONEOS_DEPLOYMENT_TARGET", "$(OFFRENT_DEPLOYMENT_TARGET)"),
    ("LOCALIZATION_PREFERS_STRING_CATALOGS", "YES"),
    ("MTL_FAST_MATH", "YES"),
    ("SDKROOT", "iphoneos"),
    ("SWIFT_VERSION", "5.0"),
    # Swift 5 language mode with complete checking: concurrency problems surface as warnings
    # rather than as errors on a first build nobody here could iterate on.
    ("SWIFT_STRICT_CONCURRENCY", "complete"),
    ("SWIFT_UPCOMING_FEATURE_CONCISE_MAGIC_FILE", "YES"),
    ("VERSIONING_SYSTEM", "apple-generic"),
    ("TARGETED_DEVICE_FAMILY", "$(OFFRENT_DEVICE_FAMILY)"),
    ("DEVELOPMENT_TEAM", "$(OFFRENT_DEVELOPMENT_TEAM)"),
    ("CODE_SIGN_STYLE", "Automatic"),
    ("ENABLE_MODULE_VERIFIER", "NO"),
]

PROJECT_DEBUG = COMMON_WARNINGS + [
    ("DEBUG_INFORMATION_FORMAT", "dwarf"),
    ("ENABLE_TESTABILITY", "YES"),
    ("GCC_DYNAMIC_NO_PIC", "NO"),
    ("GCC_OPTIMIZATION_LEVEL", "0"),
    ("GCC_PREPROCESSOR_DEFINITIONS", ["DEBUG=1", "$(inherited)"]),
    ("MTL_ENABLE_DEBUG_INFO", "INCLUDE_SOURCE"),
    ("ONLY_ACTIVE_ARCH", "YES"),
    ("SWIFT_ACTIVE_COMPILATION_CONDITIONS", "DEBUG $(inherited)"),
    ("SWIFT_OPTIMIZATION_LEVEL", "-Onone"),
]

PROJECT_RELEASE = COMMON_WARNINGS + [
    ("DEBUG_INFORMATION_FORMAT", "dwarf-with-dsym"),
    ("ENABLE_NS_ASSERTIONS", "NO"),
    ("MTL_ENABLE_DEBUG_INFO", "NO"),
    ("SWIFT_COMPILATION_MODE", "wholemodule"),
    ("SWIFT_OPTIMIZATION_LEVEL", "-O"),
    ("VALIDATE_PRODUCT", "YES"),
]

APP_SETTINGS = [
    ("ASSETCATALOG_COMPILER_APPICON_NAME", "AppIcon"),
    ("ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME", "AccentColor"),
    ("CODE_SIGN_ENTITLEMENTS", "Config/OffRentLedger.entitlements"),
    ("ENABLE_PREVIEWS", "YES"),
    ("GENERATE_INFOPLIST_FILE", "YES"),
    ("INFOPLIST_FILE", "Config/OffRentLedger-Info.plist"),
    ("INFOPLIST_KEY_CFBundleDisplayName", "$(OFFRENT_DISPLAY_NAME)"),
    ("INFOPLIST_KEY_ITSAppUsesNonExemptEncryption", "NO"),
    ("INFOPLIST_KEY_UIApplicationSceneManifest_Generation", "YES"),
    ("INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents", "YES"),
    ("INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone", "UIInterfaceOrientationPortrait"),
    ("LD_RUNPATH_SEARCH_PATHS", ["$(inherited)", "@executable_path/Frameworks"]),
    ("PRODUCT_BUNDLE_IDENTIFIER", "$(OFFRENT_BUNDLE_ID)"),
    ("PRODUCT_NAME", "$(TARGET_NAME)"),
    ("SWIFT_EMIT_LOC_STRINGS", "YES"),
]

TESTS_SETTINGS = [
    ("BUNDLE_LOADER", "$(TEST_HOST)"),
    ("GENERATE_INFOPLIST_FILE", "YES"),
    ("PRODUCT_BUNDLE_IDENTIFIER", "$(OFFRENT_TESTS_BUNDLE_ID)"),
    ("PRODUCT_NAME", "$(TARGET_NAME)"),
    ("SWIFT_EMIT_LOC_STRINGS", "NO"),
    ("TEST_HOST", "$(BUILT_PRODUCTS_DIR)/OffRentLedger.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/OffRentLedger"),
]

UITESTS_SETTINGS = [
    ("GENERATE_INFOPLIST_FILE", "YES"),
    ("PRODUCT_BUNDLE_IDENTIFIER", "$(OFFRENT_UITESTS_BUNDLE_ID)"),
    ("PRODUCT_NAME", "$(TARGET_NAME)"),
    ("SWIFT_EMIT_LOC_STRINGS", "NO"),
    ("TEST_TARGET_NAME", "OffRentLedger"),
]

WIDGET_SETTINGS = [
    ("ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME", "AccentColor"),
    ("ASSETCATALOG_COMPILER_WIDGET_BACKGROUND_COLOR_NAME", "WidgetBackground"),
    ("CODE_SIGN_ENTITLEMENTS", "Config/OffRentLedgerWidget.entitlements"),
    ("GENERATE_INFOPLIST_FILE", "YES"),
    ("INFOPLIST_FILE", "Config/OffRentLedgerWidget-Info.plist"),
    ("INFOPLIST_KEY_CFBundleDisplayName", "OffRent Summary"),
    ("INFOPLIST_KEY_NSHumanReadableCopyright", ""),
    ("LD_RUNPATH_SEARCH_PATHS", ["$(inherited)", "@executable_path/Frameworks", "@executable_path/../../Frameworks"]),
    ("PRODUCT_BUNDLE_IDENTIFIER", "$(OFFRENT_WIDGET_BUNDLE_ID)"),
    ("PRODUCT_NAME", "$(TARGET_NAME)"),
    ("SKIP_INSTALL", "YES"),
    ("SWIFT_EMIT_LOC_STRINGS", "YES"),
]

TARGET_SETTINGS = {
    T_APP: APP_SETTINGS,
    T_TESTS: TESTS_SETTINGS,
    T_UITESTS: UITESTS_SETTINGS,
    T_WIDGET: WIDGET_SETTINGS,
}

TARGET_NAMES = {
    T_APP: "OffRentLedger",
    T_TESTS: "OffRentLedgerTests",
    T_UITESTS: "OffRentLedgerUITests",
    T_WIDGET: "OffRentLedgerWidget",
}

PRODUCT_REFS = {T_APP: P_APP, T_TESTS: P_TESTS, T_UITESTS: P_UITESTS, T_WIDGET: P_WIDGET}

PRODUCT_TYPES = {
    T_APP: "com.apple.product-type.application",
    T_TESTS: "com.apple.product-type.bundle.unit-test",
    T_UITESTS: "com.apple.product-type.bundle.ui-testing",
    T_WIDGET: "com.apple.product-type.app-extension",
}

# The app compiles OffRentLedger/ and OffRentShared/; the widget compiles its own folder and the
# same OffRentShared/. That shared folder is how one definition of the App Group key, the URL
# scheme and the widget snapshot reaches both targets without a framework or a duplicated file.
SYNC_GROUPS = {
    T_APP: [(FSG_APP, "OffRentLedger"), (FSG_SHARED, "OffRentShared")],
    T_TESTS: [(FSG_TESTS, "OffRentLedgerTests")],
    T_UITESTS: [(FSG_UITESTS, "OffRentLedgerUITests")],
    T_WIDGET: [(FSG_WIDGET, "OffRentLedgerWidget"), (FSG_SHARED, "OffRentShared")],
}


def build():
    L = []
    a = L.append
    a("// !$*UTF8*$!")
    a("{")
    a("\tarchiveVersion = 1;")
    a("\tclasses = {")
    a("\t};")
    a("\tobjectVersion = 77;")
    a("\tobjects = {")

    a("\n/* Begin PBXBuildFile section */")
    a(f"\t\t{BF_WIDGET_EMBED} /* OffRentLedgerWidget.appex in Embed Foundation Extensions */ = "
      f"{{isa = PBXBuildFile; fileRef = {P_WIDGET} /* OffRentLedgerWidget.appex */; "
      f"settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};")
    a("/* End PBXBuildFile section */")

    a("\n/* Begin PBXContainerItemProxy section */")
    for proxy, target, name in [
        (PROXY_TESTS, T_APP, "OffRentLedger"),
        (PROXY_UITESTS, T_APP, "OffRentLedger"),
        (PROXY_WIDGET, T_WIDGET, "OffRentLedgerWidget"),
    ]:
        a(f"\t\t{proxy} /* PBXContainerItemProxy */ = {{")
        a("\t\t\tisa = PBXContainerItemProxy;")
        a(f"\t\t\tcontainerPortal = {PROJECT} /* Project object */;")
        a("\t\t\tproxyType = 1;")
        a(f"\t\t\tremoteGlobalIDString = {target};")
        a(f"\t\t\tremoteInfo = {name};")
        a("\t\t};")
    a("/* End PBXContainerItemProxy section */")

    a("\n/* Begin PBXCopyFilesBuildPhase section */")
    a(f"\t\t{PHASE_EMBED} /* Embed Foundation Extensions */ = {{")
    a("\t\t\tisa = PBXCopyFilesBuildPhase;")
    a("\t\t\tbuildActionMask = 2147483647;")
    a('\t\t\tdstPath = "";')
    a("\t\t\tdstSubfolderSpec = 13;")
    a("\t\t\tfiles = (")
    a(f"\t\t\t\t{BF_WIDGET_EMBED} /* OffRentLedgerWidget.appex in Embed Foundation Extensions */,")
    a("\t\t\t);")
    a('\t\t\tname = "Embed Foundation Extensions";')
    a("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    a("\t\t};")
    a("/* End PBXCopyFilesBuildPhase section */")

    a("\n/* Begin PBXFileReference section */")
    for ref, name, kind in [
        (P_APP, "OffRentLedger.app", "wrapper.application"),
        (P_TESTS, "OffRentLedgerTests.xctest", "wrapper.cfbundle"),
        (P_UITESTS, "OffRentLedgerUITests.xctest", "wrapper.cfbundle"),
        (P_WIDGET, "OffRentLedgerWidget.appex", "wrapper.app-extension"),
    ]:
        a(f'\t\t{ref} /* {name} */ = {{isa = PBXFileReference; explicitFileType = "{kind}"; '
          f"includeInIndex = 0; path = {name}; sourceTree = BUILT_PRODUCTS_DIR; }};")
    for ref, name, kind in [
        (F_XCCONFIG, "Identifiers.xcconfig", "text.xcconfig"),
        (F_APP_PLIST, "OffRentLedger-Info.plist", "text.plist.xml"),
        (F_WIDGET_PLIST, "OffRentLedgerWidget-Info.plist", "text.plist.xml"),
        (F_APP_ENTS, "OffRentLedger.entitlements", "text.plist.entitlements"),
        (F_WIDGET_ENTS, "OffRentLedgerWidget.entitlements", "text.plist.entitlements"),
        (F_STOREKIT, "OffRentLedger.storekit", "text.json"),
    ]:
        a(f'\t\t{ref} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = {kind}; '
          f'path = "{name}"; sourceTree = "<group>"; }};')
    a("/* End PBXFileReference section */")

    a("\n/* Begin PBXFileSystemSynchronizedRootGroup section */")
    for group, path in [
        (FSG_APP, "OffRentLedger"), (FSG_SHARED, "OffRentShared"),
        (FSG_TESTS, "OffRentLedgerTests"), (FSG_UITESTS, "OffRentLedgerUITests"),
        (FSG_WIDGET, "OffRentLedgerWidget"),
    ]:
        a(f'\t\t{group} /* {path} */ = {{isa = PBXFileSystemSynchronizedRootGroup; '
          f'path = {path}; sourceTree = "<group>"; }};')
    a("/* End PBXFileSystemSynchronizedRootGroup section */")

    a("\n/* Begin PBXFrameworksBuildPhase section */")
    for target in [T_APP, T_TESTS, T_UITESTS, T_WIDGET]:
        a(f"\t\t{FRAMEWORKS[target]} /* Frameworks */ = {{")
        a("\t\t\tisa = PBXFrameworksBuildPhase;")
        a("\t\t\tbuildActionMask = 2147483647;")
        a("\t\t\tfiles = (")
        a("\t\t\t);")
        a("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
        a("\t\t};")
    a("/* End PBXFrameworksBuildPhase section */")

    a("\n/* Begin PBXGroup section */")
    a(f"\t\t{MAIN_GROUP} = {{")
    a("\t\t\tisa = PBXGroup;")
    a("\t\t\tchildren = (")
    for group, name in [
        (FSG_APP, "OffRentLedger"), (FSG_SHARED, "OffRentShared"),
        (FSG_WIDGET, "OffRentLedgerWidget"),
        (FSG_TESTS, "OffRentLedgerTests"), (FSG_UITESTS, "OffRentLedgerUITests"),
        (CONFIG_GROUP, "Config"), (STOREKIT_GROUP, "StoreKit"), (PRODUCTS_GROUP, "Products"),
    ]:
        a(f"\t\t\t\t{group} /* {name} */,")
    a("\t\t\t);")
    a('\t\t\tsourceTree = "<group>";')
    a("\t\t};")

    a(f"\t\t{PRODUCTS_GROUP} /* Products */ = {{")
    a("\t\t\tisa = PBXGroup;")
    a("\t\t\tchildren = (")
    for ref, name in [(P_APP, "OffRentLedger.app"), (P_TESTS, "OffRentLedgerTests.xctest"),
                      (P_UITESTS, "OffRentLedgerUITests.xctest"), (P_WIDGET, "OffRentLedgerWidget.appex")]:
        a(f"\t\t\t\t{ref} /* {name} */,")
    a("\t\t\t);")
    a("\t\t\tname = Products;")
    a('\t\t\tsourceTree = "<group>";')
    a("\t\t};")

    a(f"\t\t{CONFIG_GROUP} /* Config */ = {{")
    a("\t\t\tisa = PBXGroup;")
    a("\t\t\tchildren = (")
    for ref, name in [(F_XCCONFIG, "Identifiers.xcconfig"), (F_APP_PLIST, "OffRentLedger-Info.plist"),
                      (F_WIDGET_PLIST, "OffRentLedgerWidget-Info.plist"),
                      (F_APP_ENTS, "OffRentLedger.entitlements"),
                      (F_WIDGET_ENTS, "OffRentLedgerWidget.entitlements")]:
        a(f"\t\t\t\t{ref} /* {name} */,")
    a("\t\t\t);")
    a("\t\t\tpath = Config;")
    a('\t\t\tsourceTree = "<group>";')
    a("\t\t};")

    a(f"\t\t{STOREKIT_GROUP} /* StoreKit */ = {{")
    a("\t\t\tisa = PBXGroup;")
    a("\t\t\tchildren = (")
    a(f"\t\t\t\t{F_STOREKIT} /* OffRentLedger.storekit */,")
    a("\t\t\t);")
    a("\t\t\tpath = StoreKit;")
    a('\t\t\tsourceTree = "<group>";')
    a("\t\t};")
    a("/* End PBXGroup section */")

    a("\n/* Begin PBXNativeTarget section */")
    for target in [T_APP, T_TESTS, T_UITESTS, T_WIDGET]:
        name = TARGET_NAMES[target]
        a(f"\t\t{target} /* {name} */ = {{")
        a("\t\t\tisa = PBXNativeTarget;")
        a(f'\t\t\tbuildConfigurationList = {CL[target]} /* Build configuration list for PBXNativeTarget "{name}" */;')
        a("\t\t\tbuildPhases = (")
        a(f"\t\t\t\t{SOURCES[target]} /* Sources */,")
        a(f"\t\t\t\t{FRAMEWORKS[target]} /* Frameworks */,")
        a(f"\t\t\t\t{RESOURCES[target]} /* Resources */,")
        if target == T_APP:
            a(f"\t\t\t\t{PHASE_EMBED} /* Embed Foundation Extensions */,")
        a("\t\t\t);")
        a("\t\t\tbuildRules = (")
        a("\t\t\t);")
        a("\t\t\tdependencies = (")
        if target == T_APP:
            a(f"\t\t\t\t{DEP_WIDGET} /* PBXTargetDependency */,")
        elif target == T_TESTS:
            a(f"\t\t\t\t{DEP_TESTS} /* PBXTargetDependency */,")
        elif target == T_UITESTS:
            a(f"\t\t\t\t{DEP_UITESTS} /* PBXTargetDependency */,")
        a("\t\t\t);")
        a("\t\t\tfileSystemSynchronizedGroups = (")
        for group, folder in SYNC_GROUPS[target]:
            a(f"\t\t\t\t{group} /* {folder} */,")
        a("\t\t\t);")
        a(f"\t\t\tname = {name};")
        a("\t\t\tpackageProductDependencies = (")
        a("\t\t\t);")
        a(f"\t\t\tproductName = {name};")
        a(f"\t\t\tproductReference = {PRODUCT_REFS[target]};")
        a(f'\t\t\tproductType = "{PRODUCT_TYPES[target]}";')
        a("\t\t};")
    a("/* End PBXNativeTarget section */")

    a("\n/* Begin PBXProject section */")
    a(f"\t\t{PROJECT} /* Project object */ = {{")
    a("\t\t\tisa = PBXProject;")
    a("\t\t\tattributes = {")
    a("\t\t\t\tBuildIndependentTargetsInParallel = 1;")
    a("\t\t\t\tLastSwiftUpdateCheck = 1600;")
    a("\t\t\t\tLastUpgradeCheck = 1600;")
    a("\t\t\t\tTargetAttributes = {")
    for target in [T_APP, T_TESTS, T_UITESTS, T_WIDGET]:
        a(f"\t\t\t\t\t{target} = {{")
        a("\t\t\t\t\t\tCreatedOnToolsVersion = 16.0;")
        if target in (T_TESTS, T_UITESTS):
            a(f"\t\t\t\t\t\tTestTargetID = {T_APP};")
        a("\t\t\t\t\t};")
    a("\t\t\t\t};")
    a("\t\t\t};")
    a(f'\t\t\tbuildConfigurationList = {CL_PROJECT} /* Build configuration list for PBXProject "OffRentLedger" */;')
    a("\t\t\tdevelopmentRegion = en;")
    a("\t\t\thasScannedForEncodings = 0;")
    a("\t\t\tknownRegions = (")
    a("\t\t\t\ten,")
    a("\t\t\t\tBase,")
    a("\t\t\t);")
    a(f"\t\t\tmainGroup = {MAIN_GROUP};")
    a("\t\t\tminimizedProjectReferenceProxies = 1;")
    a("\t\t\tpreferredProjectObjectVersion = 77;")
    a(f"\t\t\tproductRefGroup = {PRODUCTS_GROUP} /* Products */;")
    a('\t\t\tprojectDirPath = "";')
    a('\t\t\tprojectRoot = "";')
    a("\t\t\ttargets = (")
    for target in [T_APP, T_TESTS, T_UITESTS, T_WIDGET]:
        a(f"\t\t\t\t{target} /* {TARGET_NAMES[target]} */,")
    a("\t\t\t);")
    a("\t\t};")
    a("/* End PBXProject section */")

    a("\n/* Begin PBXResourcesBuildPhase section */")
    for target in [T_APP, T_TESTS, T_UITESTS, T_WIDGET]:
        a(f"\t\t{RESOURCES[target]} /* Resources */ = {{")
        a("\t\t\tisa = PBXResourcesBuildPhase;")
        a("\t\t\tbuildActionMask = 2147483647;")
        a("\t\t\tfiles = (")
        a("\t\t\t);")
        a("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
        a("\t\t};")
    a("/* End PBXResourcesBuildPhase section */")

    a("\n/* Begin PBXSourcesBuildPhase section */")
    for target in [T_APP, T_TESTS, T_UITESTS, T_WIDGET]:
        a(f"\t\t{SOURCES[target]} /* Sources */ = {{")
        a("\t\t\tisa = PBXSourcesBuildPhase;")
        a("\t\t\tbuildActionMask = 2147483647;")
        a("\t\t\tfiles = (")
        a("\t\t\t);")
        a("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
        a("\t\t};")
    a("/* End PBXSourcesBuildPhase section */")

    a("\n/* Begin PBXTargetDependency section */")
    for dep, target, name, proxy in [
        (DEP_TESTS, T_APP, "OffRentLedger", PROXY_TESTS),
        (DEP_UITESTS, T_APP, "OffRentLedger", PROXY_UITESTS),
        (DEP_WIDGET, T_WIDGET, "OffRentLedgerWidget", PROXY_WIDGET),
    ]:
        a(f"\t\t{dep} /* PBXTargetDependency */ = {{")
        a("\t\t\tisa = PBXTargetDependency;")
        a(f"\t\t\ttarget = {target} /* {name} */;")
        a(f"\t\t\ttargetProxy = {proxy} /* PBXContainerItemProxy */;")
        a("\t\t};")
    a("/* End PBXTargetDependency section */")

    a("\n/* Begin XCBuildConfiguration section */")
    for name, pairs in [("Debug", PROJECT_DEBUG), ("Release", PROJECT_RELEASE)]:
        a(f"\t\t{BC_PROJECT[name]} /* {name} */ = {{")
        a("\t\t\tisa = XCBuildConfiguration;")
        a(f"\t\t\tbaseConfigurationReference = {F_XCCONFIG} /* Identifiers.xcconfig */;")
        a("\t\t\tbuildSettings = {")
        a(settings(sorted(pairs)))
        a("\t\t\t};")
        a(f"\t\t\tname = {name};")
        a("\t\t};")
    for target in [T_APP, T_TESTS, T_UITESTS, T_WIDGET]:
        for name in ["Debug", "Release"]:
            a(f"\t\t{BC[target][name]} /* {name} */ = {{")
            a("\t\t\tisa = XCBuildConfiguration;")
            a("\t\t\tbuildSettings = {")
            a(settings(sorted(TARGET_SETTINGS[target])))
            a("\t\t\t};")
            a(f"\t\t\tname = {name};")
            a("\t\t};")
    a("/* End XCBuildConfiguration section */")

    a("\n/* Begin XCConfigurationList section */")
    a(f'\t\t{CL_PROJECT} /* Build configuration list for PBXProject "OffRentLedger" */ = {{')
    a("\t\t\tisa = XCConfigurationList;")
    a("\t\t\tbuildConfigurations = (")
    a(f"\t\t\t\t{BC_PROJECT['Debug']} /* Debug */,")
    a(f"\t\t\t\t{BC_PROJECT['Release']} /* Release */,")
    a("\t\t\t);")
    a("\t\t\tdefaultConfigurationIsVisible = 0;")
    a("\t\t\tdefaultConfigurationName = Release;")
    a("\t\t};")
    for target in [T_APP, T_TESTS, T_UITESTS, T_WIDGET]:
        name = TARGET_NAMES[target]
        a(f'\t\t{CL[target]} /* Build configuration list for PBXNativeTarget "{name}" */ = {{')
        a("\t\t\tisa = XCConfigurationList;")
        a("\t\t\tbuildConfigurations = (")
        a(f"\t\t\t\t{BC[target]['Debug']} /* Debug */,")
        a(f"\t\t\t\t{BC[target]['Release']} /* Release */,")
        a("\t\t\t);")
        a("\t\t\tdefaultConfigurationIsVisible = 0;")
        a("\t\t\tdefaultConfigurationName = Release;")
        a("\t\t};")
    a("/* End XCConfigurationList section */")

    a("\t};")
    a(f"\trootObject = {PROJECT} /* Project object */;")
    a("}")
    return "\n".join(L) + "\n"


def main():
    content = build()
    check = "--check" in sys.argv
    existing = OUT.read_text() if OUT.exists() else None
    if check:
        if existing != content:
            print("STALE: project.pbxproj differs from scripts/generate_xcodeproj.py", file=sys.stderr)
            if existing:
                for line in list(difflib.unified_diff(
                    existing.splitlines(), content.splitlines(), "committed", "generated", lineterm=""
                ))[:40]:
                    print(line, file=sys.stderr)
            return 1
        print("ok: project.pbxproj is current")
        return 0
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(content)
    print(f"wrote: {OUT.relative_to(ROOT)} ({len(content.splitlines())} lines)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
