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
  skip_targets.include?(target_name)
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

def add_flavor_build_config(project, target, base_config, flavor, bundle_id, plist_path)
  # Skip test targets to avoid Swift version conflicts
  if should_skip_target(target.name)
    log("Skipping flavor configuration for #{target.name}")
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

  # CRITICAL: Ensure simulator support for custom configurations
  new_config.build_settings['VALID_ARCHS'] = '$(ARCHS_STANDARD)'
  new_config.build_settings['ARCHS'] = '$(ARCHS_STANDARD)'
  new_config.build_settings['EXCLUDED_ARCHS[sdk=iphonesimulator*]'] = ''
  new_config.build_settings['EXCLUDED_ARCHS[sdk=iphoneos*]'] = 'i386'

  # Ensure proper build settings for simulator
  if base_config.name.downcase.include?('debug')
    new_config.build_settings['ONLY_ACTIVE_ARCH'] = 'YES'
    new_config.build_settings['ENABLE_BITCODE'] = 'NO'
  else
    new_config.build_settings['ONLY_ACTIVE_ARCH'] = 'NO'
    new_config.build_settings['ENABLE_BITCODE'] = 'YES'
  end

  # Swift and Objective-C settings
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
    project_config.build_settings.update(project.build_configuration_list.build_configurations.first.build_settings)
    project.build_configuration_list.build_configurations << project_config
    log("Added project-level configuration: #{project_config_name}")
  end
end

def create_scheme(project, target, scheme_name, flavor)
  log("Creating scheme: #{scheme_name} for flavor: #{flavor}")

  begin
    scheme = Xcodeproj::XCScheme.new

    # FIXED: Create buildable reference using proper method for xcodeproj 1.27.0
    buildable_ref = Xcodeproj::XCScheme::BuildableReference.new
    buildable_ref.target_referenced_container = "container:#{File.basename(project.path)}"
    buildable_ref.target_name = target.name
    buildable_ref.target_proxy_type = target.product_type
    buildable_ref.target_uuid = target.uuid
    buildable_ref.buildable_name = "#{target.name}.app"

    # Add build target with proper settings
    build_entry = Xcodeproj::XCScheme::BuildAction::Entry.new
    build_entry.buildable_reference = buildable_ref
    build_entry.build_for_running = true
    build_entry.build_for_testing = true
    build_entry.build_for_profiling = true
    build_entry.build_for_archiving = true
    build_entry.build_for_analyzing = true

    scheme.build_action.entries << build_entry

    # Set build configurations for different actions
    scheme.test_action.build_configuration = "Debug-#{flavor}"
    scheme.launch_action.build_configuration = "Debug-#{flavor}"
    scheme.profile_action.build_configuration = "Release-#{flavor}"
    scheme.analyze_action.build_configuration = "Debug-#{flavor}"
    scheme.archive_action.build_configuration = "Release-#{flavor}"

    # CRITICAL: Set up launch action properly
    scheme.launch_action.buildable_product_runnable = Xcodeproj::XCScheme::BuildableProductRunnable.new
    scheme.launch_action.buildable_product_runnable.buildable_reference = buildable_ref
    scheme.launch_action.buildable_product_runnable.runnable_debugging_mode = "0"

    # Set up test action
    scheme.test_action.buildable_product_runnable = Xcodeproj::XCScheme::BuildableProductRunnable.new
    scheme.test_action.buildable_product_runnable.buildable_reference = buildable_ref

    # Set up profile action
    scheme.profile_action.buildable_product_runnable = Xcodeproj::XCScheme::BuildableProductRunnable.new
    scheme.profile_action.buildable_product_runnable.buildable_reference = buildable_ref
    scheme.profile_action.buildable_product_runnable.runnable_debugging_mode = "0"

    # Save the scheme
    scheme.save_as(project.path, scheme_name, true)
    log("✅ Created scheme: #{scheme_name}")

  rescue => e
    log("❌ Failed to create scheme #{scheme_name}: #{e.message}")
    log("Error details: #{e.class} - #{e.backtrace.first}")

    # Try simpler approach
    create_scheme_simple(project, target, scheme_name, flavor)
  end
end

def create_scheme_simple(project, target, scheme_name, flavor)
  log("Creating scheme (simple method): #{scheme_name} for flavor: #{flavor}")

  begin
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

  rescue => e
    log("❌ Failed to create scheme file: #{e.message}")
    raise e
  end
end

def add_firebase_copy_phase(target)
  return if target.shell_script_build_phases.any? { |p| p.name == "Copy GoogleService-Info.plist" }

  phase = target.new_shell_script_build_phase("Copy GoogleService-Info.plist")
  phase.shell_script = <<~SCRIPT
    echo "⚡️ Selecting correct GoogleService-Info.plist for ${CONFIGURATION}"

    if [[ "${CONFIGURATION}" == *"dev"* ]]; then
      if [ -f "${PROJECT_DIR}/Runner/GoogleService-Info-dev.plist" ]; then
        cp "${PROJECT_DIR}/Runner/GoogleService-Info-dev.plist" "${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app/GoogleService-Info.plist"
        echo "✅ Copied GoogleService-Info-dev.plist"
      else
        echo "⚠️ GoogleService-Info-dev.plist not found, using default"
        cp "${PROJECT_DIR}/Runner/GoogleService-Info.plist" "${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app/GoogleService-Info.plist"
      fi
    elif [[ "${CONFIGURATION}" == *"stage"* ]]; then
      if [ -f "${PROJECT_DIR}/Runner/GoogleService-Info-stage.plist" ]; then
        cp "${PROJECT_DIR}/Runner/GoogleService-Info-stage.plist" "${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app/GoogleService-Info.plist"
        echo "✅ Copied GoogleService-Info-stage.plist"
      else
        echo "⚠️ GoogleService-Info-stage.plist not found, using default"
        cp "${PROJECT_DIR}/Runner/GoogleService-Info.plist" "${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app/GoogleService-Info.plist"
      fi
    else
      cp "${PROJECT_DIR}/Runner/GoogleService-Info.plist" "${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app/GoogleService-Info.plist"
      echo "✅ Copied default GoogleService-Info.plist"
    fi
  SCRIPT

  log("✅ Added Firebase copy script phase to target")
end

def update_project_build_settings(project, target, base_bundle_id)
  # Skip test targets when updating build settings
  if should_skip_target(target.name)
    log("Skipping build settings update for #{target.name}")
    return
  end

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

# CRITICAL FIX: Process only Runner target to avoid Swift version conflicts
project.targets.each do |target|
  next if should_skip_target(target.name)

  # Update project build settings to fix signing and simulator issues
  update_project_build_settings(project, target, base_bundle_id)

  # Add GoogleService-Info.plist copy phase
  add_firebase_copy_phase(target)
end

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

  # Create flavor-specific build configurations ONLY for Runner target
  base_configs = runner_target.build_configuration_list.build_configurations.select { |c| !c.name.include?('-') }
  base_configs.each do |base_config|
    add_flavor_build_config(project, runner_target, base_config, flavor, bundle_id, plist_relative_path)
  end

  create_scheme(project, runner_target, scheme_name, flavor)
end

project.save
log("✅ Flavors successfully configured!")
log("🔧 Please restart Xcode to see all changes")
log("📱 Simulators should now appear in scheme destinations")
puts "[INFO] Restore from backup if needed: #{backup_path}"