#!/usr/bin/env ruby
# iOS Flavor Setup Script with Firebase Run Script Phase - FIXED VERSION for xcodeproj 1.27.0

require 'xcodeproj'
require 'json'
require 'fileutils'

def log(msg)
  puts "[INFO] #{msg}"
end

# ---------------------------------------
# Constants
PROJECT_ROOT = Dir.pwd
IOS_DIR = File.join(PROJECT_ROOT, 'ios')
XCODEPROJ_PATH = File.join(IOS_DIR, 'Runner.xcodeproj')
BASE_INFO_PLIST = File.join(IOS_DIR, 'Runner', 'Info.plist')

# ---------------------------------------
# Helpers

def read_base_bundle_id
  if File.exist?(BASE_INFO_PLIST)
    content = File.read(BASE_INFO_PLIST)
    if content =~ /<key>CFBundleIdentifier<\/key>\s*<string>(.*?)<\/string>/
      match = $1.strip
      # Handle variable substitution
      if match.include?('$(PRODUCT_BUNDLE_IDENTIFIER)')
        # Try to get from build settings
        return get_bundle_id_from_build_settings
      end
      return match unless match.empty?
    end
  end

  pubspec = File.join(PROJECT_ROOT, 'pubspec.yaml')
  if File.exist?(pubspec)
    content = File.read(pubspec)
    if content =~ /(com\.[\w\.]+)/
      return $1
    end
  end

  log("⚠️ Could not determine base bundle ID, using fallback.")
  'com.example'
end

def get_bundle_id_from_build_settings
  # Try to read from existing Xcode project
  if File.exist?(XCODEPROJ_PATH)
    begin
      project = Xcodeproj::Project.open(XCODEPROJ_PATH)
      runner_target = project.targets.find { |t| t.name == 'Runner' }
      if runner_target
        debug_config = runner_target.build_configuration_list.build_configurations.find { |c| c.name == 'Debug' }
        if debug_config && debug_config.build_settings['PRODUCT_BUNDLE_IDENTIFIER']
          return debug_config.build_settings['PRODUCT_BUNDLE_IDENTIFIER']
        end
      end
    rescue => e
      log("Could not read bundle ID from project: #{e.message}")
    end
  end

  'com.example.app'
end

def clean_existing_flavor_configs(project)
  log("Cleaning existing flavor configurations...")

  # Remove flavor configurations from all targets
  project.targets.each do |target|
    configs_to_remove = target.build_configuration_list.build_configurations.select do |config|
      config.name.include?('-') && !['Debug', 'Release'].include?(config.name)
    end

    configs_to_remove.each do |config|
      target.build_configuration_list.build_configurations.delete(config)
      log("Removed config #{config.name} from target #{target.name}")
    end
  end

  # Remove flavor configurations from project level
  project_configs_to_remove = project.build_configuration_list.build_configurations.select do |config|
    config.name.include?('-') && !['Debug', 'Release'].include?(config.name)
  end

  project_configs_to_remove.each do |config|
    project.build_configuration_list.build_configurations.delete(config)
    log("Removed project config #{config.name}")
  end
end

def clear_shared_schemes(project)
  shared_schemes_dir = Xcodeproj::XCScheme.shared_data_dir(project.path)
  return unless Dir.exist?(shared_schemes_dir)

  Dir.glob(File.join(shared_schemes_dir, "*.xcscheme")).each do |scheme_path|
    File.delete(scheme_path)
    log "Removed existing scheme: #{File.basename(scheme_path)}"
  end
end

def should_skip_target(target_name)
  # Skip test targets and other non-main targets
  skip_targets = ['RunnerTests', 'RunnerUITests', 'RunnerTests (iOS)', 'RunnerUITests (iOS)']
  return true if skip_targets.include?(target_name)
  return true if target_name.downcase.include?('test')
  return true if target_name.downcase.include?('widget')
  return true if target_name.downcase.include?('extension')
  false
end

def ensure_info_plist_exists(plist_full_path, bundle_id, app_name)
  return if File.exist?(plist_full_path)

  FileUtils.mkdir_p(File.dirname(plist_full_path))
  content = <<~PLIST
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>CFBundleDisplayName</key>
      <string>#{app_name}</string>
      <key>CFBundleIdentifier</key>
      <string>#{bundle_id}</string>
      <key>CFBundleVersion</key>
      <string>$(FLUTTER_BUILD_NUMBER)</string>
      <key>CFBundleShortVersionString</key>
      <string>$(FLUTTER_BUILD_NAME)</string>
      <key>UILaunchStoryboardName</key>
      <string>LaunchScreen</string>
      <key>UISupportedInterfaceOrientations</key>
      <array>
        <string>UIInterfaceOrientationPortrait</string>
        <string>UIInterfaceOrientationLandscapeLeft</string>
        <string>UIInterfaceOrientationLandscapeRight</string>
      </array>
      <key>UISupportedInterfaceOrientations~ipad</key>
      <array>
        <string>UIInterfaceOrientationPortrait</string>
        <string>UIInterfaceOrientationPortraitUpsideDown</string>
        <string>UIInterfaceOrientationLandscapeLeft</string>
        <string>UIInterfaceOrientationLandscapeRight</string>
      </array>
      <key>LSRequiresIPhoneOS</key>
      <true/>
    </dict>
    </plist>
  PLIST

  File.write(plist_full_path, content)
  log("Auto-created missing Info.plist at #{plist_full_path}")
end

def ensure_consistent_swift_version(project)
  log("Ensuring consistent Swift version across all targets...")

  # Get the Swift version from the Runner target
  runner_target = project.targets.find { |t| t.name == 'Runner' }
  base_swift_version = nil

  if runner_target
    debug_config = runner_target.build_configuration_list.build_configurations.find { |c| c.name == 'Debug' }
    if debug_config
      base_swift_version = debug_config.build_settings['SWIFT_VERSION'] || '5.0'
    end
  end

  base_swift_version ||= '5.0'
  log("Using Swift version: #{base_swift_version}")

  # Apply consistent Swift version to all targets
  project.targets.each do |target|
    target.build_configuration_list.build_configurations.each do |config|
      config.build_settings['SWIFT_VERSION'] = base_swift_version
    end
    log("Updated Swift version for target: #{target.name}")
  end
end

def add_flavor_build_config(project, target, base_config, flavor, bundle_id, plist_path)
  # CRITICAL: Only create flavor configs for the Runner target
  if target.name != 'Runner'
    log("Skipping flavor configuration for non-Runner target: #{target.name}")
    return
  end

  new_config_name = "#{base_config.name}-#{flavor}"
  log("Creating build configuration: #{new_config_name} for target: #{target.name}")

  # Check if configuration already exists
  existing_config = target.build_configuration_list.build_configurations.find { |c| c.name == new_config_name }
  if existing_config
    log("Configuration #{new_config_name} already exists, updating...")
    new_config = existing_config
  else
    new_config = project.new(Xcodeproj::Project::Object::XCBuildConfiguration)
    new_config.name = new_config_name
    target.build_configuration_list.build_configurations << new_config
  end

  # Copy all settings from base config
  new_config.build_settings.clear
  new_config.build_settings.update(base_config.build_settings)

  # Set the actual bundle identifier (not a variable)
  new_config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = bundle_id
  new_config.build_settings['INFOPLIST_FILE'] = plist_path

  # CRITICAL: Keep Flutter's expected build configurations
  new_config.build_settings['FLUTTER_BUILD_MODE'] = base_config.build_settings['FLUTTER_BUILD_MODE']
  new_config.build_settings['FLUTTER_TARGET'] = base_config.build_settings['FLUTTER_TARGET'] || 'lib/main.dart'

  # Fix signing settings for automatic signing
  new_config.build_settings['CODE_SIGN_STYLE'] = 'Automatic'
  new_config.build_settings['DEVELOPMENT_TEAM'] = base_config.build_settings['DEVELOPMENT_TEAM'] || ''

  # Remove manual signing settings that might conflict
  new_config.build_settings.delete('CODE_SIGN_IDENTITY')
  new_config.build_settings.delete('PROVISIONING_PROFILE_SPECIFIER')

  # Ensure proper signing for debug/release
  if base_config.name.downcase.include?('debug')
    new_config.build_settings['CODE_SIGN_IDENTITY[sdk=iphoneos*]'] = 'iPhone Developer'
  else
    new_config.build_settings['CODE_SIGN_IDENTITY[sdk=iphoneos*]'] = 'iPhone Distribution'
  end

  # Let the new config inherit most architecture settings from the base config.
  # Flutter's base configs are usually set up correctly.
  # We only ensure ONLY_ACTIVE_ARCH is correctly set for Debug.
  if base_config.name.downcase.include?('debug')
    new_config.build_settings['ONLY_ACTIVE_ARCH'] = 'YES'
  end

  # Swift and Objective-C settings - ensure consistency
  new_config.build_settings['SWIFT_OPTIMIZATION_LEVEL'] = base_config.build_settings['SWIFT_OPTIMIZATION_LEVEL']
  new_config.build_settings['SWIFT_VERSION'] = base_config.build_settings['SWIFT_VERSION'] || '5.0'

  # Deployment target
  new_config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = base_config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] || '12.0'

  # Add flavor-specific settings
  new_config.build_settings['FLUTTER_FLAVOR'] = flavor
  new_config.build_settings['DART_DEFINES'] = "FLAVOR=#{flavor}"

  # CRITICAL: Ensure the configuration can be used for running
  new_config.build_settings['PRODUCT_NAME'] = '$(TARGET_NAME)'
  new_config.build_settings['EXECUTABLE_NAME'] = '$(EXECUTABLE_NAME)'

  # Add to project level build configuration list as well
  project_config_name = new_config_name
  existing_project_config = project.build_configuration_list.build_configurations.find { |c| c.name == project_config_name }

  unless existing_project_config
    project_config = project.new(Xcodeproj::Project::Object::XCBuildConfiguration)
    project_config.name = project_config_name

    # Copy base project config settings
    base_project_config = project.build_configuration_list.build_configurations.find { |c| c.name == base_config.name }
    if base_project_config
      project_config.build_settings.update(base_project_config.build_settings)
    end

    project.build_configuration_list.build_configurations << project_config
    log("Added project-level configuration: #{project_config_name}")
  end
end

def create_scheme(project, target, scheme_name, flavor)
  log("Creating scheme: #{scheme_name} for flavor: #{flavor}")

  # Create scheme directory if it doesn't exist
  schemes_dir = File.join(project.path, 'xcshareddata', 'xcschemes')
  FileUtils.mkdir_p(schemes_dir)

  # Create scheme file content manually
  scheme_content = <<~SCHEME
    <?xml version="1.0" encoding="UTF-8"?>
    <Scheme
       LastUpgradeVersion = "1500"
       version = "1.3">
       <BuildAction
          parallelizeBuildables = "YES"
          buildImplicitDependencies = "YES">
          <BuildActionEntries>
             <BuildActionEntry
                buildForTesting = "YES"
                buildForRunning = "YES"
                buildForProfiling = "YES"
                buildForArchiving = "YES"
                buildForAnalyzing = "YES">
                <BuildableReference
                   BuildableIdentifier = "primary"
                   BlueprintIdentifier = "#{target.uuid}"
                   BuildableName = "#{target.name}.app"
                   BlueprintName = "#{target.name}"
                   ReferencedContainer = "container:#{File.basename(project.path)}">
                </BuildableReference>
             </BuildActionEntry>
          </BuildActionEntries>
       </BuildAction>
       <TestAction
          buildConfiguration = "Debug-#{flavor}"
          selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
          selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
          shouldUseLaunchSchemeArgsEnv = "YES">
          <BuildableProductRunnable
             runnableDebuggingMode = "0">
             <BuildableReference
                BuildableIdentifier = "primary"
                BlueprintIdentifier = "#{target.uuid}"
                BuildableName = "#{target.name}.app"
                BlueprintName = "#{target.name}"
                ReferencedContainer = "container:#{File.basename(project.path)}">
             </BuildableReference>
          </BuildableProductRunnable>
       </TestAction>
       <LaunchAction
          buildConfiguration = "Debug-#{flavor}"
          selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
          selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
          launchStyle = "0"
          useCustomWorkingDirectory = "NO"
          ignoresPersistentStateOnLaunch = "NO"
          debugDocumentVersioning = "YES"
          debugServiceExtension = "internal"
          allowLocationSimulation = "YES">
          <BuildableProductRunnable
             runnableDebuggingMode = "0">
             <BuildableReference
                BuildableIdentifier = "primary"
                BlueprintIdentifier = "#{target.uuid}"
                BuildableName = "#{target.name}.app"
                BlueprintName = "#{target.name}"
                ReferencedContainer = "container:#{File.basename(project.path)}">
             </BuildableReference>
          </BuildableProductRunnable>
       </LaunchAction>
       <ProfileAction
          buildConfiguration = "Release-#{flavor}"
          shouldUseLaunchSchemeArgsEnv = "YES"
          savedToolIdentifier = ""
          useCustomWorkingDirectory = "NO"
          debugDocumentVersioning = "YES">
          <BuildableProductRunnable
             runnableDebuggingMode = "0">
             <BuildableReference
                BuildableIdentifier = "primary"
                BlueprintIdentifier = "#{target.uuid}"
                BuildableName = "#{target.name}.app"
                BlueprintName = "#{target.name}"
                ReferencedContainer = "container:#{File.basename(project.path)}">
             </BuildableReference>
          </BuildableProductRunnable>
       </ProfileAction>
       <AnalyzeAction
          buildConfiguration = "Debug-#{flavor}">
       </AnalyzeAction>
       <ArchiveAction
          buildConfiguration = "Release-#{flavor}"
          revealArchiveInOrganizer = "YES">
       </ArchiveAction>
    </Scheme>
  SCHEME

  scheme_file = File.join(schemes_dir, "#{scheme_name}.xcscheme")
  File.write(scheme_file, scheme_content)
  log("✅ Created scheme file: #{scheme_file}")
end

def add_firebase_copy_phase(target)
  # Only add to Runner target
  return unless target.name == 'Runner'

  # Remove existing Firebase copy phases to avoid duplicates
  existing_phases = target.shell_script_build_phases.select { |p| p.name == "Copy GoogleService-Info.plist" }
  existing_phases.each do |phase|
    target.build_phases.delete(phase)
    log("Removed existing Firebase copy phase")
  end

  phase = target.new_shell_script_build_phase("Copy GoogleService-Info.plist")
  phase.shell_script = <<~SCRIPT
    echo "⚡️ Running Firebase GoogleService-Info.plist copy phase"

    if [ "${TARGET_NAME}" != "Runner" ]; then
      echo "Skipping copy phase for non-app target: ${TARGET_NAME}"
      exit 0
    fi

    PLIST_NAME="GoogleService-Info.plist"
    DEST="${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app/${PLIST_NAME}"

    FLAVOR="${CONFIGURATION##*-}"

    SOURCE="${PROJECT_DIR}/Runner/flavors/${FLAVOR}/${PLIST_NAME}"

    if [ -f "${SOURCE}" ]; then
      cp "${SOURCE}" "${DEST}"
      echo "✅ Copied ${SOURCE} to ${DEST}"
    else
      echo "⚠️ Flavor-specific plist not found for flavor '${FLAVOR}', falling back to default"

      DEFAULT_SOURCE="${PROJECT_DIR}/Runner/${PLIST_NAME}"
      if [ -f "${DEFAULT_SOURCE}" ]; then
        cp "${DEFAULT_SOURCE}" "${DEST}"
        echo "✅ Copied default ${DEFAULT_SOURCE} to ${DEST}"
      else
        echo "⚠️ No default ${DEFAULT_SOURCE} found either, skipping copy"
      fi
    fi
  SCRIPT

  log("✅ Added Firebase copy script phase to target")
end

def debug_final_configuration(project, target)
  log("=== FINAL CONFIGURATION DEBUG ===")

  # Check what configurations were actually created
  all_configs = target.build_configuration_list.build_configurations
  flavor_configs = all_configs.select { |c| c.name.include?('-') }

  log("Total configurations: #{all_configs.length}")
  log("Flavor configurations: #{flavor_configs.length}")

  flavor_configs.each do |config|
    log("Configuration: #{config.name}")
    log("  Bundle ID: #{config.build_settings['PRODUCT_BUNDLE_IDENTIFIER']}")
    log("  Info.plist: #{config.build_settings['INFOPLIST_FILE']}")
    log("  Code Sign Style: #{config.build_settings['CODE_SIGN_STYLE']}")
    log("  Flutter Flavor: #{config.build_settings['FLUTTER_FLAVOR']}")
    log("  Dart Defines: #{config.build_settings['DART_DEFINES']}")
    log("  Swift Version: #{config.build_settings['SWIFT_VERSION']}")
    log("  Flutter Build Mode: #{config.build_settings['FLUTTER_BUILD_MODE']}")
    log("  Flutter Target: #{config.build_settings['FLUTTER_TARGET']}")

    # Check if Info.plist actually exists
    plist_path = config.build_settings['INFOPLIST_FILE']
    if plist_path
      full_path = File.join(IOS_DIR, plist_path)
      exists = File.exist?(full_path)
      log("  Info.plist exists: #{exists}")
      if !exists
        log("  ❌ MISSING: #{full_path}")
      end
    end
    log("  ---")
  end

  # Check schemes
  schemes_dir = File.join(XCODEPROJ_PATH, 'xcshareddata', 'xcschemes')
  if Dir.exist?(schemes_dir)
    schemes = Dir.glob(File.join(schemes_dir, "*.xcscheme"))
    log("Schemes created: #{schemes.map { |s| File.basename(s, '.xcscheme') }.join(', ')}")
  else
    log("❌ No schemes directory found")
  end
end

def update_project_build_settings(project, target, base_bundle_id)
  # Only update Runner target build settings
  return unless target.name == 'Runner'

  # Update project-level build settings
  project.build_configuration_list.build_configurations.each do |config|
    # Only update non-flavor configurations at project level
    next if config.name.include?('-')

    # Ensure PRODUCT_BUNDLE_IDENTIFIER is set at project level
    config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = base_bundle_id

    # Fix common signing issues
    config.build_settings['CODE_SIGN_STYLE'] = 'Automatic'
    config.build_settings['DEVELOPMENT_TEAM'] = config.build_settings['DEVELOPMENT_TEAM'] || ''

    # Remove conflicting settings
    config.build_settings.delete('PROVISIONING_PROFILE_SPECIFIER')
    config.build_settings.delete('CODE_SIGN_IDENTITY')

    # Set proper architectures for simulator support
    config.build_settings['VALID_ARCHS'] = '$(ARCHS_STANDARD)'
    config.build_settings['ARCHS'] = '$(ARCHS_STANDARD)'
    config.build_settings['EXCLUDED_ARCHS[sdk=iphonesimulator*]'] = ''
    config.build_settings['EXCLUDED_ARCHS[sdk=iphoneos*]'] = 'i386'

    # Ensure simulator support
    if config.name.downcase.include?('debug')
      config.build_settings['ONLY_ACTIVE_ARCH'] = 'YES'
      config.build_settings['ENABLE_BITCODE'] = 'NO'
    else
      config.build_settings['ONLY_ACTIVE_ARCH'] = 'NO'
      config.build_settings['ENABLE_BITCODE'] = 'YES'
    end

    # Deployment target
    config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] || '12.0'
  end

  # Update target-level build settings
  target.build_configuration_list.build_configurations.each do |config|
    next if config.name.include?('-') # Skip flavor configs, they're handled separately

    config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = base_bundle_id
    config.build_settings['CODE_SIGN_STYLE'] = 'Automatic'
    config.build_settings['DEVELOPMENT_TEAM'] = config.build_settings['DEVELOPMENT_TEAM'] || ''

    # Ensure proper simulator support
    config.build_settings['VALID_ARCHS'] = '$(ARCHS_STANDARD)'
    config.build_settings['ARCHS'] = '$(ARCHS_STANDARD)'
    config.build_settings['EXCLUDED_ARCHS[sdk=iphonesimulator*]'] = ''
    config.build_settings['EXCLUDED_ARCHS[sdk=iphoneos*]'] = 'i386'

    if config.name.downcase.include?('debug')
      config.build_settings['ONLY_ACTIVE_ARCH'] = 'YES'
      config.build_settings['ENABLE_BITCODE'] = 'NO'
    else
      config.build_settings['ONLY_ACTIVE_ARCH'] = 'NO'
      config.build_settings['ENABLE_BITCODE'] = 'YES'
    end

    # Deployment target
    config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] || '12.0'
  end
end

def create_generated_config_file(project, flavors)
  # Create Generated.xcconfig file that Flutter expects
  generated_config_path = File.join(IOS_DIR, 'Flutter', 'Generated.xcconfig')

  # Ensure Flutter directory exists
  FileUtils.mkdir_p(File.dirname(generated_config_path))

  # Read existing content or create new
  existing_content = ""
  if File.exist?(generated_config_path)
    existing_content = File.read(generated_config_path)
  end

  # Add flavor configurations if not already present
  flavor_configs = flavors.map { |flavor| "FLAVOR_#{flavor.upcase}=#{flavor}" }.join("\n")

  unless existing_content.include?("FLAVOR_")
    File.write(generated_config_path, "#{existing_content}\n#{flavor_configs}\n")
    log("Updated Generated.xcconfig with flavor configurations")
  end
end

# ---------------------------------------
# Script Entry
if ARGV.length != 1
  puts "Usage: ruby ios_flavor_setup.rb path/to/flavor_configs.json"
  exit 1
end

flavor_config_path = ARGV[0]
unless File.exist?(flavor_config_path)
  puts "[ERROR] Config file not found: #{flavor_config_path}"
  exit 1
end

begin
  flavor_configs = JSON.parse(File.read(flavor_config_path))
rescue JSON::ParserError => e
  puts "[ERROR] Invalid JSON: #{e.message}"
  exit 1
end

if flavor_configs.empty?
  puts "[ERROR] No flavors in config file."
  exit 1
end

unless Dir.exist?(XCODEPROJ_PATH)
  puts "[ERROR] Runner.xcodeproj not found at: #{XCODEPROJ_PATH}"
  exit 1
end

project = Xcodeproj::Project.open(XCODEPROJ_PATH)
runner_target = project.targets.find { |t| t.name == 'Runner' }
unless runner_target
  puts "[ERROR] Could not find 'Runner' target in Xcode project."
  exit 1
end

base_bundle_id = read_base_bundle_id
log("Base bundle ID: #{base_bundle_id}")

# Create backup
backup_path = "#{XCODEPROJ_PATH}.backup.#{Time.now.to_i}"
FileUtils.cp_r(XCODEPROJ_PATH, backup_path)
log("Backup created at: #{backup_path}")

# Clean existing flavor configurations first
clean_existing_flavor_configs(project)

# Clear existing schemes
clear_shared_schemes(project)

# CRITICAL: Ensure consistent Swift version across all targets BEFORE creating new configs
ensure_consistent_swift_version(project)

# Process only Runner target to update base build settings and add Firebase copy phase
update_project_build_settings(project, runner_target, base_bundle_id)
add_firebase_copy_phase(runner_target)

# Extract flavor names for Generated.xcconfig
flavor_names = flavor_configs.map { |entry| entry['flavor'] }

# Main loop - Process flavors only for Runner target
flavor_configs.each do |entry|
  flavor = entry['flavor']
  ios_config = entry['iOS'] || {}

  scheme_name = ios_config['schemeName'] || flavor
  bundle_id_suffix = ios_config['bundleIdSuffix'] || ".#{flavor}"
  display_name_suffix = ios_config['displayNameSuffix'] || " #{flavor.capitalize}"

  plist_relative_path = "Runner/flavors/#{flavor}/Info.plist"
  plist_full_path = File.join(IOS_DIR, plist_relative_path)

  bundle_id = "#{base_bundle_id}#{bundle_id_suffix}"
  app_name = "MyApp#{display_name_suffix}"

  log("Processing flavor: #{flavor}")
  log("  - Bundle ID: #{bundle_id}")
  log("  - App Name: #{app_name}")
  log("  - Scheme: #{scheme_name}")

  ensure_info_plist_exists(plist_full_path, bundle_id, app_name)

  # Create flavor-specific build configurations only for Runner
  base_configs = runner_target.build_configuration_list.build_configurations.select do |c|
    ['Debug', 'Release'].include?(c.name)
  end
  base_configs.each do |base_config|
    add_flavor_build_config(project, runner_target, base_config, flavor, bundle_id, plist_relative_path)
  end

  # Create scheme
  create_scheme(project, runner_target, scheme_name, flavor)
end

# Create or update Generated.xcconfig
create_generated_config_file(project, flavor_names)

debug_final_configuration(project, runner_target)

project.save
log("✅ Flavors successfully configured!")
log("🔧 Please restart Xcode to see all changes")
log("📱 Run 'flutter clean' and 'flutter build ios' to regenerate build artifacts")
puts "[INFO] Restore from backup if needed: #{backup_path}"