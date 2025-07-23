#!/usr/bin/env ruby
# iOS Flavor Removal Script - Enhanced Version with Complete Cleanup
# Removes all flavors and restores project to normal state or keeps specified flavor

require 'xcodeproj'
require 'json'
require 'fileutils'
require 'readline'

def log(msg)
  puts "[INFO] #{msg}"
end

def error(msg)
  puts "[ERROR] #{msg}"
end

def warning(msg)
  puts "[WARNING] #{msg}"
end

# Constants
PROJECT_ROOT = Dir.pwd
IOS_DIR = File.join(PROJECT_ROOT, 'ios')
XCODEPROJ_PATH = File.join(IOS_DIR, 'Runner.xcodeproj')
BASE_INFO_PLIST = File.join(IOS_DIR, 'Runner', 'Info.plist')
PODFILE_PATH = File.join(IOS_DIR, 'Podfile')
GENERATED_CONFIG_PATH = File.join(IOS_DIR, 'Flutter', 'Generated.xcconfig')

# Create backup before starting removal
def create_removal_backup
  backup_path = "#{XCODEPROJ_PATH}.removal_backup.#{Time.now.to_i}"
  log("Creating backup before removal...")

  begin
    FileUtils.cp_r(XCODEPROJ_PATH, backup_path)

    # Also backup Podfile if exists
    if File.exist?(PODFILE_PATH)
      FileUtils.cp(PODFILE_PATH, "#{PODFILE_PATH}.removal_backup.#{Time.now.to_i}")
    end

    # Backup Generated.xcconfig if exists
    if File.exist?(GENERATED_CONFIG_PATH)
      FileUtils.cp(GENERATED_CONFIG_PATH, "#{GENERATED_CONFIG_PATH}.removal_backup.#{Time.now.to_i}")
    end

    log("✅ Backup created at: #{backup_path}")
    return backup_path
  rescue => e
    error("Failed to create backup: #{e.message}")
    return nil
  end
end

# Restore from backup if removal fails
def restore_from_backup(backup_path)
  return unless backup_path && File.exist?(backup_path)

  log("🔄 Restoring from backup due to failure...")

  begin
    # Restore xcodeproj
    FileUtils.rm_rf(XCODEPROJ_PATH) if File.exist?(XCODEPROJ_PATH)
    FileUtils.cp_r(backup_path, XCODEPROJ_PATH)

    # Restore Podfile
    podfile_backup = "#{PODFILE_PATH}.removal_backup.#{File.basename(backup_path).split('.').last}"
    if File.exist?(podfile_backup)
      FileUtils.cp(podfile_backup, PODFILE_PATH)
      FileUtils.rm(podfile_backup)
    end

    # Restore Generated.xcconfig
    config_backup = "#{GENERATED_CONFIG_PATH}.removal_backup.#{File.basename(backup_path).split('.').last}"
    if File.exist?(config_backup)
      FileUtils.cp(config_backup, GENERATED_CONFIG_PATH)
      FileUtils.rm(config_backup)
    end

    log("✅ Successfully restored from backup")
  rescue => e
    error("Failed to restore from backup: #{e.message}")
  end
end

# Remove backup after successful removal
def cleanup_backup(backup_path)
  return unless backup_path && File.exist?(backup_path)

  begin
    FileUtils.rm_rf(backup_path)

    # Clean up other backup files
    backup_timestamp = File.basename(backup_path).split('.').last
    ["#{PODFILE_PATH}.removal_backup.#{backup_timestamp}",
     "#{GENERATED_CONFIG_PATH}.removal_backup.#{backup_timestamp}"].each do |file|
      FileUtils.rm(file) if File.exist?(file)
    end

    log("✅ Cleanup: Removed backup files")
  rescue => e
    warning("Could not cleanup backup files: #{e.message}")
  end
end

# Detect existing flavors from project
def detect_existing_flavors(project)
  flavors = Set.new

  # Look for flavor-specific build configurations
  project.build_configuration_list.build_configurations.each do |config|
    if config.name.include?('-') && !['Debug', 'Release'].include?(config.name)
      # Extract flavor from config name like "Debug-dev" -> "dev"
      flavor = config.name.split('-').last
      flavors.add(flavor)
    end
  end

  # Also check filesystem for flavor folders
  flavors_dir = File.join(IOS_DIR, 'Runner', 'flavors')
  if Dir.exist?(flavors_dir)
    Dir.entries(flavors_dir).each do |entry|
      next if entry == '.' || entry == '..'
      next unless File.directory?(File.join(flavors_dir, entry))
      flavors.add(entry)
    end
  end

  flavors.to_a.sort
end

# Detect flavor schemes
def detect_flavor_schemes
  schemes = []
  schemes_dir = File.join(XCODEPROJ_PATH, 'xcshareddata', 'xcschemes')

  if Dir.exist?(schemes_dir)
    Dir.entries(schemes_dir).each do |entry|
      next if entry == '.' || entry == '..'
      next unless entry.end_with?('.xcscheme')

      scheme_name = entry.sub('.xcscheme', '')
      # Skip default Runner scheme
      next if scheme_name == 'Runner'

      schemes << scheme_name
    end
  end

  schemes.sort
end

# Remove ALL file references related to flavors
def remove_flavor_file_references(project, flavors_to_remove)
  log("🧹 Removing file references for flavors: #{flavors_to_remove.join(', ')}")

  # Remove PBXFileReference entries for flavor files
  project.main_group.recursive_children.delete_if do |child|
    should_remove = false

    if child.respond_to?(:path) && child.path
      # Check if this is a flavor-related file
      flavors_to_remove.each do |flavor|
        if child.path.include?("flavors/#{flavor}") ||
           child.path.include?("flavors/#{flavor.capitalize}") ||
           child.path.include?("GoogleService-Info.plist") && child.path.include?(flavor)
          should_remove = true
          log("Removing file reference: #{child.path}")
          break
        end
      end
    end

    should_remove
  end

  # Remove PBXBuildFile entries for flavor files
  project.objects.each do |obj|
    if obj.isa == 'PBXBuildFile' && obj.file_ref
      file_ref = obj.file_ref
      if file_ref.respond_to?(:path) && file_ref.path
        flavors_to_remove.each do |flavor|
          if file_ref.path.include?("flavors/#{flavor}") ||
             file_ref.path.include?("flavors/#{flavor.capitalize}") ||
             (file_ref.path.include?("GoogleService-Info.plist") && file_ref.path.include?(flavor))
            project.objects.delete(obj)
            log("Removed build file reference: #{file_ref.path}")
            break
          end
        end
      end
    end
  end
end

# Remove flavor-specific build configurations
def remove_flavor_build_configs(project, flavors_to_remove)
  log("🧹 Removing build configurations for flavors: #{flavors_to_remove.join(', ')}")

  # Remove from project level
  project.build_configuration_list.build_configurations.delete_if do |config|
    should_remove = false

    if config.name.include?('-')
      flavor = config.name.split('-').last
      should_remove = flavors_to_remove.include?(flavor)
    end

    if should_remove
      log("Removed project config: #{config.name}")
    end

    should_remove
  end

  # Remove from all targets
  project.targets.each do |target|
    target.build_configuration_list.build_configurations.delete_if do |config|
      should_remove = false

      if config.name.include?('-')
        flavor = config.name.split('-').last
        should_remove = flavors_to_remove.include?(flavor)
      end

      if should_remove
        log("Removed config #{config.name} from target #{target.name}")
      end

      should_remove
    end
  end
end

# Remove flavor schemes
def remove_flavor_schemes(flavors_to_remove)
  log("🧹 Removing schemes for flavors: #{flavors_to_remove.join(', ')}")

  schemes_dir = File.join(XCODEPROJ_PATH, 'xcshareddata', 'xcschemes')
  return unless Dir.exist?(schemes_dir)

  Dir.entries(schemes_dir).each do |entry|
    next if entry == '.' || entry == '..'
    next unless entry.end_with?('.xcscheme')

    scheme_name = entry.sub('.xcscheme', '')

    if flavors_to_remove.include?(scheme_name)
      scheme_path = File.join(schemes_dir, entry)
      File.delete(scheme_path)
      log("Removed scheme: #{scheme_name}")
    end
  end
end

# Remove flavor folders and files
def remove_flavor_files(flavors_to_remove)
  log("🧹 Removing flavor files for: #{flavors_to_remove.join(', ')}")

  flavors_dir = File.join(IOS_DIR, 'Runner', 'flavors')
  return unless Dir.exist?(flavors_dir)

  flavors_to_remove.each do |flavor|
    [flavor, flavor.capitalize, flavor.downcase].each do |flavor_variant|
      flavor_path = File.join(flavors_dir, flavor_variant)
      if Dir.exist?(flavor_path)
        FileUtils.rm_rf(flavor_path)
        log("Removed flavor directory: #{flavor_path}")
      end
    end
  end

  # Remove flavors directory if empty
  if Dir.exist?(flavors_dir) && Dir.entries(flavors_dir).size <= 2 # only . and ..
    FileUtils.rm_rf(flavors_dir)
    log("Removed empty flavors directory")
  end
end

# Remove Firebase copy script phase
def remove_firebase_copy_phase(project)
  log("🧹 Removing Firebase copy script phase")

  project.targets.each do |target|
    target.shell_script_build_phases.delete_if do |phase|
      if phase.name == "Copy GoogleService-Info.plist"
        log("Removed Firebase copy script phase from target #{target.name}")
        true
      else
        false
      end
    end
  end
end

# Clean up all resource build phases
def clean_resource_build_phases(project, flavors_to_remove)
  log("🧹 Cleaning resource build phases")

  project.targets.each do |target|
    target.resources_build_phase.files.delete_if do |build_file|
      if build_file.file_ref && build_file.file_ref.path
        flavors_to_remove.each do |flavor|
          if build_file.file_ref.path.include?("flavors/#{flavor}") ||
             build_file.file_ref.path.include?("flavors/#{flavor.capitalize}") ||
             (build_file.file_ref.path.include?("GoogleService-Info.plist") && build_file.file_ref.path.include?(flavor))
            log("Removed resource build file: #{build_file.file_ref.path}")
            return true
          end
        end
      end
      false
    end
  end
end

# Restore Podfile to original state
def restore_podfile_to_original
  return unless File.exist?(PODFILE_PATH)

  log("🔄 Restoring Podfile to original state")

  content = File.read(PODFILE_PATH)

  # Remove the project block with flavor configurations
  content.gsub!(/project\s+'Runner'.*?\}\s*\n/m, '')

  # Ensure platform line is uncommented
  content.gsub!(/^#\s*platform\s+:ios/, 'platform :ios')

  # Clean up extra newlines
  content.gsub!(/\n{3,}/, "\n\n")

  File.write(PODFILE_PATH, content)
  log("✅ Podfile restored to original state")
end

# Update Podfile for single flavor as default
def update_podfile_for_single_flavor(flavor_to_keep)
  return unless File.exist?(PODFILE_PATH)

  log("🔄 Updating Podfile to use #{flavor_to_keep} as default configuration")

  content = File.read(PODFILE_PATH)

  # Build new project block with the kept flavor as default
  new_project_block = "project 'Runner', {\n"
  new_project_block += "  'Debug' => :debug,\n"
  new_project_block += "  'Profile' => :release,\n"
  new_project_block += "  'Release' => :release,\n"
  new_project_block += "  'Debug-#{flavor_to_keep}' => :debug,\n"
  new_project_block += "  'Release-#{flavor_to_keep}' => :release,\n"
  new_project_block += "}\n"

  if content.match(/project\s+'Runner'.*?\}/m)
    content.gsub!(/project\s+'Runner'.*?\}/m, new_project_block)
  else
    # Insert before target
    content.sub!(/(target\s+')/, "#{new_project_block}\n\\1")
  end

  File.write(PODFILE_PATH, content)
  log("✅ Podfile updated with #{flavor_to_keep} as default")
end

# Update build configurations to make flavor default
def update_build_configs_for_default_flavor(project, flavor_to_keep)
  log("🔄 Setting #{flavor_to_keep} as default configuration")

  # Update project level configurations
  project.build_configuration_list.build_configurations.each do |config|
    if config.name == "Debug-#{flavor_to_keep}"
      # Copy settings from flavor config to Debug
      debug_config = project.build_configuration_list.build_configurations.find { |c| c.name == 'Debug' }
      if debug_config
        debug_config.build_settings.merge!(config.build_settings)
      end
    elsif config.name == "Release-#{flavor_to_keep}"
      # Copy settings from flavor config to Release
      release_config = project.build_configuration_list.build_configurations.find { |c| c.name == 'Release' }
      if release_config
        release_config.build_settings.merge!(config.build_settings)
      end
    end
  end

  # Update target configurations
  project.targets.each do |target|
    target.build_configuration_list.build_configurations.each do |config|
      if config.name == "Debug-#{flavor_to_keep}"
        debug_config = target.build_configuration_list.build_configurations.find { |c| c.name == 'Debug' }
        if debug_config
          debug_config.build_settings.merge!(config.build_settings)
        end
      elsif config.name == "Release-#{flavor_to_keep}"
        release_config = target.build_configuration_list.build_configurations.find { |c| c.name == 'Release' }
        if release_config
          release_config.build_settings.merge!(config.build_settings)
        end
      end
    end
  end

  log("✅ Default configurations updated with #{flavor_to_keep} settings")
end

# Restore Generated.xcconfig to original state
def restore_generated_config_to_original
  return unless File.exist?(GENERATED_CONFIG_PATH)

  log("🔄 Restoring Generated.xcconfig to original state")

  content = File.read(GENERATED_CONFIG_PATH)

  # Remove flavor-specific lines
  lines = content.split("\n")
  cleaned_lines = lines.reject { |line| line.include?('FLAVOR_') }

  File.write(GENERATED_CONFIG_PATH, cleaned_lines.join("\n"))
  log("✅ Generated.xcconfig restored")
end

# Copy flavor configuration files to main Runner directory and update project references
def copy_flavor_files_to_main_and_update_project(project, flavor_to_keep)
  log("🔄 Setting up #{flavor_to_keep} as default configuration")

  flavors_dir = File.join(IOS_DIR, 'Runner', 'flavors')
  main_runner_dir = File.join(IOS_DIR, 'Runner')

  # Try different case variations of the flavor name
  flavor_variants = [flavor_to_keep, flavor_to_keep.capitalize, flavor_to_keep.downcase]

  flavor_found = false

  flavor_variants.each do |flavor_variant|
    flavor_path = File.join(flavors_dir, flavor_variant)
    next unless Dir.exist?(flavor_path)

    log("Found flavor directory: #{flavor_path}")
    flavor_found = true

    # Copy Info.plist if it exists
    flavor_info_plist = File.join(flavor_path, 'Info.plist')
    main_info_plist = File.join(main_runner_dir, 'Info.plist')

    if File.exist?(flavor_info_plist)
      FileUtils.cp(flavor_info_plist, main_info_plist)
      log("✅ Copied Info.plist from #{flavor_variant} to main Runner directory")
    end

    # Copy GoogleService-Info.plist if it exists and is not a dummy
    flavor_google_plist = File.join(flavor_path, 'GoogleService-Info.plist')
    main_google_plist = File.join(main_runner_dir, 'GoogleService-Info.plist')

    if File.exist?(flavor_google_plist)
      content = File.read(flavor_google_plist)
      # Only copy if it's not a dummy file
      unless content.include?('Dummy') || content.include?('Replace this file')
        FileUtils.cp(flavor_google_plist, main_google_plist)
        log("✅ Copied GoogleService-Info.plist from #{flavor_variant} to main Runner directory")
      else
        log("⚠️  Skipping dummy GoogleService-Info.plist from #{flavor_variant}")
        # Remove dummy file if it exists in main directory
        FileUtils.rm(main_google_plist) if File.exist?(main_google_plist)
      end
    end

    # Copy any other configuration files (excluding known files)
    Dir.entries(flavor_path).each do |entry|
      next if entry == '.' || entry == '..' || entry == 'Info.plist' || entry == 'GoogleService-Info.plist'

      source_file = File.join(flavor_path, entry)
      next unless File.file?(source_file)

      dest_file = File.join(main_runner_dir, entry)
      FileUtils.cp(source_file, dest_file)
      log("✅ Copied #{entry} from #{flavor_variant} to main Runner directory")
    end

    break # Found and processed the flavor, no need to check other variants
  end

  unless flavor_found
    warning("Flavor directory not found for: #{flavor_to_keep}")
  end


  # Update project file references to point to main Runner directory files
  update_project_file_references_for_default(project, flavor_to_keep)
end

# Update project file references to use main directory files instead of flavor-specific ones
def update_project_file_references_for_default(project, flavor_to_keep)
  log("🔄 Updating project file references for default configuration")

  project.main_group.recursive_children.each do |child|
    next unless child.respond_to?(:path) && child.path

    # Update GoogleService-Info.plist references to point to main directory
    if child.path.include?("GoogleService-Info.plist") &&
       (child.path.include?("flavors/#{flavor_to_keep}") ||
        child.path.include?("flavors/#{flavor_to_keep.capitalize}") ||
        child.path.include?("flavors/#{flavor_to_keep.downcase}"))

      child.path = "GoogleService-Info.plist"
      log("Updated file reference to main GoogleService-Info.plist")
    end

    # Update Info.plist references if they were flavor-specific
    if child.path.include?("Info.plist") && child.path.include?("flavors/")
      child.path = "Info.plist"
      log("Updated file reference to main Info.plist")
    end
  end
end

# Clean up any remaining flavor-specific files in main directory
def cleanup_main_directory_flavor_files
  log("🧹 Cleaning up main directory from any flavor-specific files")

  main_runner_dir = File.join(IOS_DIR, 'Runner')

  # Remove GoogleService-Info.plist if it exists and is dummy
  google_plist = File.join(main_runner_dir, 'GoogleService-Info.plist')
  if File.exist?(google_plist)
    # Only remove if it's a dummy file, keep real ones
    content = File.read(google_plist)
    if content.include?('Dummy') || content.include?('Replace this file')
      FileUtils.rm(google_plist)
      log("Removed dummy GoogleService-Info.plist from main directory")
    end
  end
end

# Perform complete restoration
def perform_complete_restoration(project, all_flavors)
  log("🔄 Performing complete restoration (removing all flavors and restoring to original state)")

  # Remove file references first
  remove_flavor_file_references(project, all_flavors)

  # Clean resource build phases
  clean_resource_build_phases(project, all_flavors)

  # Remove all flavor configurations
  remove_flavor_build_configs(project, all_flavors)

  # Remove all flavor schemes
  remove_flavor_schemes(all_flavors)

  # Remove Firebase copy phase
  remove_firebase_copy_phase(project)

  # Remove all flavor files
  remove_flavor_files(all_flavors)

  # Restore Podfile
  restore_podfile_to_original

  # Restore Generated.xcconfig
  restore_generated_config_to_original

  # Clean up any remaining flavor-specific files in main directory
  cleanup_main_directory_flavor_files()

  log("✅ Complete restoration finished - project restored to original state")
end

# Ensure Info.plist exists in main directory
def ensure_main_info_plist_exists
  main_info_plist = File.join(IOS_DIR, 'Runner', 'Info.plist')

  unless File.exist?(main_info_plist)
    log("⚠️  Main Info.plist not found, creating default one...")

    default_info_plist_content = <<~PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>$(DEVELOPMENT_LANGUAGE)</string>
	<key>CFBundleDisplayName</key>
	<string>$(PRODUCT_NAME)</string>
	<key>CFBundleExecutable</key>
	<string>$(EXECUTABLE_NAME)</string>
	<key>CFBundleIdentifier</key>
	<string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>$(PRODUCT_NAME)</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>$(FLUTTER_BUILD_NAME)</string>
	<key>CFBundleSignature</key>
	<string>????</string>
	<key>CFBundleVersion</key>
	<string>$(FLUTTER_BUILD_NUMBER)</string>
	<key>LSRequiresIPhoneOS</key>
	<true/>
	<key>UILaunchStoryboardName</key>
	<string>LaunchScreen</string>
	<key>UIMainStoryboardFile</key>
	<string>Main</string>
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
	<key>CADisableMinimumFrameDurationOnPhone</key>
	<true/>
	<key>UIApplicationSupportsIndirectInputEvents</key>
	<true/>
</dict>
</plist>
PLIST

    File.write(main_info_plist, default_info_plist_content)
    log("✅ Created default Info.plist")
  end
end

def ensure_info_plist_reference_exists(project)
  log("🔍 Ensuring Info.plist reference exists in project")

  # Check if Info.plist file reference exists
  info_plist_ref = nil
  project.main_group.recursive_children.each do |child|
    if child.respond_to?(:path) && child.path == 'Info.plist'
      info_plist_ref = child
      break
    end
  end

  # If no reference exists, create one
  if info_plist_ref.nil?
    log("Creating Info.plist file reference")
    runner_group = project.main_group.find_subpath('Runner', true)
    info_plist_ref = runner_group.new_reference('Info.plist')
    info_plist_ref.source_tree = '<group>'
  end

  # Ensure all targets have INFOPLIST_FILE build setting
  project.targets.each do |target|
    target.build_configuration_list.build_configurations.each do |config|
      if config.build_settings['INFOPLIST_FILE'].nil? ||
         config.build_settings['INFOPLIST_FILE'].include?('flavors/')
        config.build_settings['INFOPLIST_FILE'] = '$(SRCROOT)/Runner/Info.plist'
        log("Set INFOPLIST_FILE for #{target.name} - #{config.name}")
      end
    end
  end
end

def validate_and_cleanup_project(project)
  log("🔍 Validating and cleaning up project references...")

  # Remove ALL file references that point to flavor directories
  project.main_group.recursive_children.delete_if do |child|
    if child.respond_to?(:path) && child.path && child.path.include?('flavors/')
      log("Removing file reference: #{child.path}")
      true
    else
      false
    end
  end

  # Clean up build phases
  project.targets.each do |target|
    target.build_phases.each do |build_phase|
      next unless build_phase.respond_to?(:files)

      build_phase.files.delete_if do |build_file|
        if build_file.file_ref && build_file.file_ref.path && build_file.file_ref.path.include?('flavors/')
          log("Removed build file reference: #{build_file.file_ref.path}")
          true
        else
          false
        end
      end
    end
  end

  log("✅ Project validation and cleanup completed")
end

# REPLACE the existing perform_selective_restoration_with_default function with this:
def perform_selective_restoration_with_default(project, all_flavors, flavor_to_keep)
  log("🔄 Setting #{flavor_to_keep} as the default configuration and removing all other flavors")

  # STEP 1: Ensure main Info.plist exists
  ensure_main_info_plist_exists

  # STEP 1.5: CRITICAL FIX - Ensure project references are correct
  ensure_info_plist_reference_exists(project)

  # STEP 2: Copy the kept flavor's files to main Runner directory and update references
  copy_flavor_files_to_main_and_update_project(project, flavor_to_keep)

  # STEP 3: Copy the kept flavor's build settings to default configurations
  update_build_configs_for_default_flavor(project, flavor_to_keep)

  # STEP 4: Update ALL file references to point to main directory (not flavor directories)
  update_all_file_references_to_main_directory(project, all_flavors, flavor_to_keep)

  # STEP 5: Clean ALL resource build phases of flavor references
  clean_resource_build_phases(project, all_flavors)

  # STEP 6: Remove ALL flavor build configurations (including the kept one since settings are now in default)
  remove_flavor_build_configs(project, all_flavors)

  # STEP 7: Remove ALL flavor schemes
  remove_flavor_schemes(all_flavors)

  # STEP 8: Remove Firebase copy phase (not needed since files are now in main directory)
  remove_firebase_copy_phase(project)

  # STEP 9: Validate and clean up any remaining invalid references
  validate_and_cleanup_project(project)

  # STEP 10: Remove ALL flavor directories (do this AFTER updating references)
  remove_flavor_files(all_flavors)

  # STEP 11: Restore Podfile to original state (no flavor configs needed)
  restore_podfile_to_original

  # STEP 12: Restore Generated.xcconfig
  restore_generated_config_to_original

  # STEP 14: Final cleanup of project references
  final_cleanup_project_references(project)


  log("✅ #{flavor_to_keep} is now the default configuration - all flavor infrastructure removed")
end


def update_all_file_references_to_main_directory(project, all_flavors, flavor_to_keep)
  log("🔄 Updating all file references to point to main Runner directory")

  # Update all file references that point to flavor directories
  project.main_group.recursive_children.each do |child|
    next unless child.respond_to?(:path) && child.path

    all_flavors.each do |flavor|
      # Update any file that references a flavor directory to point to main directory instead
      if child.path.include?("flavors/#{flavor}") ||
         child.path.include?("flavors/#{flavor.capitalize}") ||
         child.path.include?("flavors/#{flavor.downcase}")

        # Extract just the filename
        filename = File.basename(child.path)

        # Point to main Runner directory
        child.path = filename
        log("Updated file reference from flavor directory to main: #{filename}")
      end
    end
  end

  # Also update any build phase file references
  project.targets.each do |target|
    # Check all build phases for file references
    target.build_phases.each do |build_phase|
      next unless build_phase.respond_to?(:files)

      build_phase.files.each do |build_file|
        next unless build_file.file_ref && build_file.file_ref.path

        all_flavors.each do |flavor|
          if build_file.file_ref.path.include?("flavors/#{flavor}") ||
             build_file.file_ref.path.include?("flavors/#{flavor.capitalize}") ||
             build_file.file_ref.path.include?("flavors/#{flavor.downcase}")

            filename = File.basename(build_file.file_ref.path)
            build_file.file_ref.path = filename
            log("Updated build file reference to main directory: #{filename}")
          end
        end
      end
    end
  end
end



# Parse command line arguments
def parse_arguments
  flavor_to_keep = ARGV[0]&.strip

  if flavor_to_keep.nil? || flavor_to_keep.empty?
    return { option: 'complete', flavor_to_keep: nil }
  else
    return { option: 'selective', flavor_to_keep: flavor_to_keep }
  end
end

# Validate flavor against detected flavors
def validate_flavor_choice(flavor_to_keep, detected_flavors)
  return true if flavor_to_keep.nil? # Complete restoration is always valid

  unless detected_flavors.include?(flavor_to_keep)
    error("Invalid flavor name: '#{flavor_to_keep}'")
    error("Available flavors: #{detected_flavors.join(', ')}")
    return false
  end

  true
end

def final_cleanup_project_references(project)
  log("🧹 Final cleanup of any remaining flavor references in project file")

  # Remove any remaining file references to flavor directories
  project.objects.each do |obj|
    if obj.isa == 'PBXFileReference' && obj.path && obj.path.include?('flavors/')
      project.objects.delete(obj)
      log("Removed orphaned file reference: #{obj.path}")
    end
  end

  # Clean up build file references
  project.objects.each do |obj|
    if obj.isa == 'PBXBuildFile' && obj.file_ref && obj.file_ref.path && obj.file_ref.path.include?('flavors/')
      project.objects.delete(obj)
      log("Removed orphaned build file reference")
    end
  end
end

# Main execution
def main
  # Check if we're in the right directory
  unless Dir.exist?(XCODEPROJ_PATH)
    error("Runner.xcodeproj not found at: #{XCODEPROJ_PATH}")
    error("Please run this script from the Flutter project root directory")
    exit 1
  end

  # Create backup
  backup_path = create_removal_backup
  unless backup_path
    error("Could not create backup. Aborting for safety.")
    exit 1
  end

  begin
    # Load project
    project = Xcodeproj::Project.open(XCODEPROJ_PATH)
    log("✅ Loaded Xcode project")

    # Detect existing flavors
    detected_flavors = detect_existing_flavors(project)

    if detected_flavors.empty?
      log("No flavors detected in the project. Nothing to remove.")
      cleanup_backup(backup_path)
      exit 0
    end

    # Parse command line arguments
    choice = parse_arguments

    # Validate flavor choice
    unless validate_flavor_choice(choice[:flavor_to_keep], detected_flavors)
      cleanup_backup(backup_path)
      exit 1
    end

    # Log the operation
    if choice[:option] == 'complete'
      log("🔄 Performing complete restoration (removing all flavors)")
    else
      log("🔄 Keeping flavor '#{choice[:flavor_to_keep]}' as default configuration")
    end

    # Perform restoration based on choice
    case choice[:option]
    when 'complete'
      perform_complete_restoration(project, detected_flavors)
    when 'selective'
      perform_selective_restoration_with_default(project, detected_flavors, choice[:flavor_to_keep])
    end

    # In perform_complete_restoration function, add before the final log:
    final_cleanup_project_references(project)

    # In perform_selective_restoration_with_default function, add before the final log:
    final_cleanup_project_references(project)

    # Save project
    project.save
    log("✅ Project saved successfully")

    # Clean up backup since operation was successful
    cleanup_backup(backup_path)

    puts "\n" + "="*60
    puts "🎉 FLAVOR REMOVAL COMPLETED SUCCESSFULLY!"
    puts "="*60

    if choice[:option] == 'complete'
      puts "📱 All flavors removed. Project restored to original state."
    else
      puts "📱 Flavor '#{choice[:flavor_to_keep]}' is now the default configuration."
    end

    puts "🔧 Please run 'flutter clean' and rebuild your project"
    puts "🔧 Run 'cd ios && pod install && cd ..' to update Pod dependencies"
    puts "🔧 Restart Xcode to see all changes"

  rescue => e
    error("Removal failed: #{e.message}")
    error("Restoring from backup...")

    restore_from_backup(backup_path)

    puts "\n" + "="*60
    puts "❌ FLAVOR REMOVAL FAILED"
    puts "="*60
    puts "Project has been restored from backup"
    puts "Error: #{e.message}"

    exit 1
  end
end

# def validate_and_cleanup_project(project)
#   log("🔍 Validating project for any remaining flavor references...")
#
#   issues_found = false
#
#   # Check for any remaining flavor file references
#   project.main_group.recursive_children.each do |child|
#     next unless child.respond_to?(:path) && child.path
#
#     if child.path.include?('flavors/') && !File.exist?(File.join(IOS_DIR, 'Runner', child.path))
#       warning("Found reference to missing file: #{child.path}")
#       issues_found = true
#
#       # Remove the reference
#       child.remove_from_project
#       log("Removed invalid file reference: #{child.path}")
#     end
#   end
#
#   # Check build phases for invalid file references
#   project.targets.each do |target|
#     target.build_phases.each do |build_phase|
#       next unless build_phase.respond_to?(:files)
#
#       build_phase.files.delete_if do |build_file|
#         if build_file.file_ref && build_file.file_ref.path &&
#            build_file.file_ref.path.include?('flavors/') &&
#            !File.exist?(File.join(IOS_DIR, 'Runner', build_file.file_ref.path))
#
#           log("Removed invalid build file reference: #{build_file.file_ref.path}")
#           true
#         else
#           false
#         end
#       end
#     end
#   end
#
#   if issues_found
#     log("✅ Project validation completed - fixed invalid references")
#   else
#     log("✅ Project validation passed - no issues found")
#   end
# end







# Run the script
if __FILE__ == $0
  main
end

