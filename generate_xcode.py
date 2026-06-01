#!/usr/bin/env python3
"""Generate a valid Xcode project for OpenSource Shelf."""
import os, hashlib, uuid

def xid(s):
    return hashlib.sha256(s.encode()).hexdigest()[:24].upper()

sources = []
for root, _, files in os.walk("OpenSourceShelf"):
    for f in sorted(files):
        if f.endswith(".swift"):
            sources.append(os.path.join(root, f))

file_ids = {s: xid(f"f:{s}") for s in sources}
bf_ids = {s: xid(f"bf:{s}") for s in sources}

PID = xid("project")
MGID = xid("mainGroup")
PGID = xid("productsGroup")
TID = xid("target")
BCLID = xid("buildConfigList")
BCDID = xid("debugConfig")
BCRID = xid("releaseConfig")
SBPID = xid("sourcesPhase")
PRID = xid("productRef")
NTID = xid("nativeTarget")
PXPID = xid("PBXProject")
FBPID = xid("frameworksPhase")
GRDB_PACKAGE_ID = xid("package:GRDB.swift")
GRDB_PRODUCT_ID = xid("product:GRDB")
GRDB_BUILD_FILE_ID = xid("buildFile:GRDB")

lines = []
def L(txt): lines.append(txt)

L("// !$*UTF8*$!")
L("{")
L("\tarchiveVersion = 1;")
L("\tclasses = {};")
L("\tobjectVersion = 60;")
L("\tobjects = {")

# File references
for src in sources:
    name = os.path.basename(src)
    fid = file_ids[src]
    L(f"\t\t{fid} /* {name} */ = {{")
    L(f"\t\t\tisa = PBXFileReference;")
    L(f"\t\t\tlastKnownFileType = sourcecode.swift;")
    L(f"\t\t\tname = \"{name}\";")
    L(f"\t\t\tpath = \"{src}\";")
    L(f"\t\t\tsourceTree = SOURCE_ROOT;")
    L(f"\t\t}};")

# Product ref
L(f"\t\t{PRID} /* OpenSource Shelf.app */ = {{")
L(f"\t\t\tisa = PBXFileReference;")
L(f"\t\t\texplicitFileType = wrapper.application;")
L(f"\t\t\tincludeInIndex = 0;")
L(f"\t\t\tpath = \"OpenSource Shelf.app\";")
L(f"\t\t\tsourceTree = BUILT_PRODUCTS_DIR;")
L(f"\t\t}};")

# Main group
L(f"\t\t{MGID} = {{")
L(f"\t\t\tisa = PBXGroup;")
L(f"\t\t\tchildren = (")
for src in sources:
    L(f"\t\t\t\t{file_ids[src]} /* {os.path.basename(src)} */,")
L(f"\t\t\t\t{PGID} /* Products */,")
L(f"\t\t\t);")
L(f"\t\t\tsourceTree = \"<group>\";")
L(f"\t\t}};")

# Products group
L(f"\t\t{PGID} = {{")
L(f"\t\t\tisa = PBXGroup;")
L(f"\t\t\tchildren = (")
L(f"\t\t\t\t{PRID} /* OpenSource Shelf.app */,")
L(f"\t\t\t);")
L(f"\t\t\tname = Products;")
L(f"\t\t\tsourceTree = \"<group>\";")
L(f"\t\t}};")

# Build files
for src in sources:
    L(f"\t\t{bf_ids[src]} /* in Sources */ = {{")
    L(f"\t\t\tisa = PBXBuildFile;")
    L(f"\t\t\tfileRef = {file_ids[src]};")
    L(f"\t\t}};")

L(f"\t\t{GRDB_BUILD_FILE_ID} /* GRDB in Frameworks */ = {{")
L(f"\t\t\tisa = PBXBuildFile;")
L(f"\t\t\tproductRef = {GRDB_PRODUCT_ID} /* GRDB */;")
L(f"\t\t}};")

# Native target
L(f"\t\t{NTID} = {{")
L(f"\t\t\tisa = PBXNativeTarget;")
L(f"\t\t\tbuildConfigurationList = {BCLID};")
L(f"\t\t\tbuildPhases = (")
L(f"\t\t\t\t{SBPID},")
L(f"\t\t\t\t{FBPID},")
L(f"\t\t\t);")
L(f"\t\t\tbuildRules = (")
L(f"\t\t\t);")
L(f"\t\t\tdependencies = (")
L(f"\t\t\t);")
L(f"\t\t\tname = \"OpenSource Shelf\";")
L(f"\t\t\tproductName = \"OpenSource Shelf\";")
L(f"\t\t\tproductReference = {PRID};")
L(f"\t\t\tproductType = \"com.apple.product-type.application\";")
L(f"\t\t\tpackageProductDependencies = (")
L(f"\t\t\t\t{GRDB_PRODUCT_ID} /* GRDB */,")
L(f"\t\t\t);")
L(f"\t\t}};")

# Sources build phase
L(f"\t\t{SBPID} = {{")
L(f"\t\t\tisa = PBXSourcesBuildPhase;")
L(f"\t\t\trunOnlyForDeploymentPostprocessing = 0;")
L(f"\t\t\tfiles = (")
for src in sources:
    L(f"\t\t\t\t{bf_ids[src]},")
L(f"\t\t\t);")
L(f"\t\t}};")

# Frameworks build phase
L(f"\t\t{FBPID} /* Frameworks */ = {{")
L(f"\t\t\tisa = PBXFrameworksBuildPhase;")
L(f"\t\t\tbuildActionMask = 2147483647;")
L(f"\t\t\tfiles = (")
L(f"\t\t\t\t{GRDB_BUILD_FILE_ID} /* GRDB in Frameworks */,")
L(f"\t\t\t);")
L(f"\t\t\trunOnlyForDeploymentPostprocessing = 0;")
L(f"\t\t}};")

# Build configs
L(f"\t\t{BCLID} = {{")
L(f"\t\t\tisa = XCConfigurationList;")
L(f"\t\t\tbuildConfigurations = (")
L(f"\t\t\t\t{BCDID}, {BCRID},")
L(f"\t\t\t);")
L(f"\t\t\tdefaultConfigurationIsVisible = 0;")
L(f"\t\t\tdefaultConfigurationName = Release;")
L(f"\t\t}};")

for cid, cname in [(BCDID, "Debug"), (BCRID, "Release")]:
    L(f"\t\t{cid} = {{")
    L(f"\t\t\tisa = XCBuildConfiguration;")
    L(f"\t\t\tbuildSettings = {{")
    L(f"\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;")
    L(f"\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;")
    L(f"\t\t\t\tCODE_SIGN_STYLE = Automatic;")
    L(f"\t\t\t\tCOMBINE_HIDPI_IMAGES = YES;")
    L(f"\t\t\t\tENABLE_PREVIEWS = YES;")
    L(f"\t\t\t\tINFOPLIST_FILE = \"OpenSourceShelf/Info.plist\";")
    L(f"\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (")
    L(f"\t\t\t\t\t\"$(inherited)\",")
    L(f"\t\t\t\t\t\"@executable_path/../Frameworks\",")
    L(f"\t\t\t\t);")
    L(f"\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 14.0;")
    L(f"\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.kika.opensourceshelf;")
    L(f"\t\t\t\tPRODUCT_NAME = \"$(TARGET_NAME)\";")
    if cname == "Debug":
        L(f"\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;")
    L(f"\t\t\t\tSWIFT_VERSION = 5.0;")
    L(f"\t\t\t}};")
    L(f"\t\t\tname = {cname};")
    L(f"\t\t}};")

# PBXProject
L(f"\t\t{PXPID} = {{")
L(f"\t\t\tisa = PBXProject;")
L(f"\t\t\tattributes = {{ BuildIndependentTargetsInParallel = 1; }};")
L(f"\t\t\tbuildConfigurationList = {BCLID};")
L(f"\t\t\tcompatibilityVersion = \"Xcode 15.0\";")
L(f"\t\t\tdevelopmentRegion = en;")
L(f"\t\t\thasScannedForEncodings = 0;")
L(f"\t\t\tknownRegions = (en,);")
L(f"\t\t\tmainGroup = {MGID};")
L(f"\t\t\tpackageReferences = (")
L(f"\t\t\t\t{GRDB_PACKAGE_ID} /* XCRemoteSwiftPackageReference \"GRDB.swift\" */,")
L(f"\t\t\t);")
L(f"\t\t\tproductRefGroup = {PGID};")
L(f"\t\t\tprojectDirPath = \"\";")
L(f"\t\t\tprojectRoot = \"\";")
L(f"\t\t\ttargets = ({NTID},);")
L(f"\t\t}};")

# Swift package dependency
L(f"\t\t{GRDB_PRODUCT_ID} /* GRDB */ = {{")
L(f"\t\t\tisa = XCSwiftPackageProductDependency;")
L(f"\t\t\tpackage = {GRDB_PACKAGE_ID} /* XCRemoteSwiftPackageReference \"GRDB.swift\" */;")
L(f"\t\t\tproductName = GRDB;")
L(f"\t\t}};")

L(f"\t\t{GRDB_PACKAGE_ID} /* XCRemoteSwiftPackageReference \"GRDB.swift\" */ = {{")
L(f"\t\t\tisa = XCRemoteSwiftPackageReference;")
L(f"\t\t\trepositoryURL = \"https://github.com/groue/GRDB.swift.git\";")
L(f"\t\t\trequirement = {{")
L(f"\t\t\t\tkind = upToNextMajorVersion;")
L(f"\t\t\t\tminimumVersion = 7.10.0;")
L(f"\t\t\t}};")
L(f"\t\t}};")

L("\t};")
L(f"\trootObject = {PXPID} /* Project object */;")
L("}")

os.makedirs("OpenSourceShelf.xcodeproj", exist_ok=True)
with open("OpenSourceShelf.xcodeproj/project.pbxproj", "w") as f:
    f.write("\n".join(lines))

print(f"Generated Xcode project with {len(sources)} source files")
