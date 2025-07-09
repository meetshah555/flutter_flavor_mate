#!/usr/bin/env ruby

# iOS Flavor Setup Script for Flutter Projects

gem 'xcodeproj', '= 1.27.0'
require 'json'
require 'xcodeproj'
require 'fileutils'
require 'rexml/document'

BASE_BUNDLE_ID = 'com.example' # Customize this for your app

def create_flavor_info_plist(flavor_config, project_root, base_app_name)
  flavor = flavor_config['flavor']
  ios_config = flavor_config['iOS'] || {}
  display_name_suffix = ios_config['displayNameSuffix'] || " #{flavor.capitalize}"
  bundle_id_suffix = ios_config['bundleIdSuffix'] || ".#{flavor}"

  flavors_dir = File.join(project_root, 'ios', 'Runner', 'flavors', flavor)
  FileUtils.mkdir_p(flavors_dir)
  info_plist_path = File.join(flavors_dir, 'Info.plist')

  bundle_identifier = "#{BASE_BUNDLE_ID}.#{base_app_name.downcase}#{bundle_id_suffix}"

  info_plist_content = <<~PLIST
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>CFBundleDisplayName</key>
      <string>#{base_app_name}#{display_name_suffix}</string>
      <key>CFBundleIdentifier</key>
      <string>#{bundle_identifier}</string>
      <key>CFBundleVersion</key>
      <string>$(FLUTTER_BUILD_NUMBER)</string>
      <key>CFBundleShortVersionString</key>
      <string>$(FLUTTER_BUILD_NAME)</string>
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
      <key>UIRequiredDeviceCapabilities</key>
      <array>
        <string>arm64</string>
      </array>
    </dict>
    </plist>
  PLIST

  File.write(info_plist_path, info_plist_content)
  puts "[INFO] Created Info.plist for #{flavor} at #{info_plist_path}"
end

def ensure_project_has_configuration(project, config_name)
  existing = project.build_configurations.find { |c| c.name == config_name }
  return if existing

  puts "[INFO] Adding project-level build configuration '#{config_name}'"

  base_config = if config_name.include?("Debug")
                  project.build_configurations.find { |c| c.name.downcase.include?("debug") }
                elsif config_name.include?("Release")
                  project.build_configurations.find { |c| c.name.downcase.include?("release") }
                elsif config_name.include?("Profile")
                  project.build_configurations.find { |c| c.name.downcase.include?("profile") }
                end

  new_config = project.new(Xcodeproj::Project::Object::XCBuildConfiguration)
  new_config.name = config_name
  new_config.build_settings = base_config&.build_settings&.dup || {}

  project.build_configuration_list.build_configurations << new_config
end

def duplicate_target(project, base_target, flavor)
  new_target_name = "Runner-#{flavor}"
  puts "[INFO] Creating new app target: #{new_target_name}"

  new_target = project.new_target(
    base_target.symbol_type,
    new_target_name,
    base_target.platform_name,
    base_target.deployment_target
  )
  new_target.product_name = new_target_name
  new_target.product_type = base_target.product_type

  product_name = "#{new_target_name}.app"
  new_target.product_reference = project.products_group.new_file(product_name)

  puts "[INFO] Adding Sources, Resources, Frameworks phases..."
  %w[Sources Resources Frameworks].each do |phase|
    new_target.build_phases << project.new(Xcodeproj::Project::Object.const_get("PBX#{phase}BuildPhase"))
  end

  new_target
end

def create_build_configurations(project, target, flavor, base_app_name)
  puts "[INFO] Updating build configurations for #{target.name}"

  bundle_id_suffix = ".#{flavor}"
  bundle_identifier = "#{BASE_BUNDLE_ID}.#{base_app_name.downcase}#{bundle_id_suffix}"

  target.build_configuration_list.build_configurations.each do |config|
    original_name = config.name
    new_name = "#{original_name}-#{flavor}"

    config.build_settings['PRODUCT_NAME'] = target.name
    config.build_settings['INFOPLIST_FILE'] = "Runner/flavors/#{flavor}/Info.plist"
    config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = bundle_identifier
    config.build_settings['TARGETED_DEVICE_FAMILY'] = '1,2'

    current_defines = config.build_settings['DART_DEFINES'] || ''
    unless current_defines.include?("FLAVOR=#{flavor}")
      config.build_settings['DART_DEFINES'] = current_defines.empty? ? "FLAVOR=#{flavor}" : "#{current_defines},FLAVOR=#{flavor}"
    end

    config.name = new_name
    puts "[INFO] Renamed build configuration '#{original_name}' to '#{new_name}'"

    # ✅ Ensure matching config exists in project-level
    ensure_project_has_configuration(project, new_name)
  end
end

def create_scheme(project, target, flavor)
  puts "[INFO] Creating scheme for #{flavor}..."

  schemes_dir = Xcodeproj::XCScheme.shared_data_dir(project.path)
  FileUtils.mkdir_p(schemes_dir)

  new_scheme_path = File.join(schemes_dir, "#{flavor}.xcscheme")

  scheme = Xcodeproj::XCScheme.new

  # Add the target to the Build action
  scheme.add_build_target(target)

  # Set build configurations
  scheme.launch_action.build_configuration = "Debug-#{flavor}"
  scheme.test_action.build_configuration = "Debug-#{flavor}"
  scheme.profile_action.build_configuration = "Release-#{flavor}"
  scheme.analyze_action.build_configuration = "Debug-#{flavor}"
  scheme.archive_action.build_configuration = "Release-#{flavor}"

  # Save it
  scheme.save_as(project.path, flavor, true)

  puts "[INFO] Created Xcode scheme: #{new_scheme_path}"
end


# --- MAIN EXECUTION ---

if ARGV.length != 1
  puts "Usage: ruby ios_flavor_setup.rb path/to/flavor_configs.json"
  exit 1
end

config_file = ARGV[0]
unless File.exist?(config_file)
  puts "[ERROR] Config file not found: #{config_file}"
  exit 1
end

begin
  configs = JSON.parse(File.read(config_file))
rescue JSON::ParserError => e
  puts "[ERROR] Invalid JSON in config file: #{e.message}"
  exit 1
end

if configs.empty?
  puts "[ERROR] No flavors found in config file."
  exit 1
end

project_root = Dir.pwd
ios_project_path = File.join(project_root, 'ios', 'Runner.xcodeproj')

unless File.exist?(ios_project_path)
  puts "[ERROR] Xcode project not found at: #{ios_project_path}"
  exit 1
end

begin
  project = Xcodeproj::Project.open(ios_project_path)
rescue => e
  puts "[ERROR] Could not open Xcode project: #{e.message}"
  exit 1
end

base_target = project.targets.find { |t| t.name == 'Runner' }
if base_target.nil?
  puts "[ERROR] Could not find 'Runner' target in Xcode project."
  exit 1
end

base_app_name = configs.first["baseAppName"] || "MyApp"
backup_path = "#{ios_project_path}.backup.#{Time.now.to_i}"
FileUtils.cp_r(ios_project_path, backup_path)
puts "[INFO] Created backup at: #{backup_path}"

begin
  configs.each do |config|
    flavor = config["flavor"]
    puts "\n--- Setting up flavor: #{flavor} ---"

    create_flavor_info_plist(config, project_root, base_app_name)
    new_target = duplicate_target(project, base_target, flavor)
    create_build_configurations(project, new_target, flavor, base_app_name)
    create_scheme(project, new_target, flavor)
  end

  runner_scheme_path = File.join(Xcodeproj::XCScheme.shared_data_dir(project.path), 'Runner.xcscheme')
  FileUtils.rm(runner_scheme_path) if File.exist?(runner_scheme_path)
  puts "\n[INFO] Removed original 'Runner' scheme."

  project.save
  puts "\n✅ [SUCCESS] iOS flavor setup complete!"
  puts "[INFO] You can now open Xcode and select the dev/stage scheme."

rescue => e
  puts "\n❌ [ERROR] Script failed: #{e.message}"
  puts "[INFO] Restoring from backup..."
  FileUtils.rm_rf(ios_project_path)
  FileUtils.cp_r(backup_path, ios_project_path)
  puts "[INFO] Backup restored. Please check the error and try again."
  exit 1
end
