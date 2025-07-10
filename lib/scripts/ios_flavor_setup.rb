#!/usr/bin/env ruby
# iOS Flavor Setup Script (Xcodeproj) - Correct Flutter style
require 'xcodeproj'
require 'json'
require 'fileutils'

BASE_BUNDLE_ID = 'com.example'
RUNNER_TARGET_NAME = 'Runner'

def log(msg)
  puts "[INFO] #{msg}"
end

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

project_root = Dir.pwd
xcodeproj_path = File.join(project_root, 'ios', 'Runner.xcodeproj')
unless Dir.exist?(xcodeproj_path)
  puts "[ERROR] Runner.xcodeproj not found at: #{xcodeproj_path}"
  exit 1
end

project = Xcodeproj::Project.open(xcodeproj_path)
runner_target = project.targets.find { |t| t.name == RUNNER_TARGET_NAME }
unless runner_target
  puts "[ERROR] Could not find 'Runner' target in Xcode project."
  exit 1
end

backup_path = "#{xcodeproj_path}.backup.#{Time.now.to_i}"
FileUtils.cp_r(xcodeproj_path, backup_path)
log("Backup created at: #{backup_path}")

def add_flavor_build_config(project, target, base_config, flavor, bundle_id_suffix, plist_path)
  new_config_name = "#{base_config.name}-#{flavor}"
  log("Creating build configuration: #{new_config_name}")

  new_config = project.new(Xcodeproj::Project::Object::XCBuildConfiguration)
  new_config.name = new_config_name
  new_config.build_settings.update(base_config.build_settings)
  new_config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = "#{BASE_BUNDLE_ID}#{bundle_id_suffix}"
  new_config.build_settings['INFOPLIST_FILE'] = plist_path
  target.build_configuration_list.build_configurations << new_config
end

def create_flavor_plist(flavor, bundle_id, plist_path, app_name)
  FileUtils.mkdir_p(File.dirname(plist_path))
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
      </array>
      <key>LSRequiresIPhoneOS</key>
      <true/>
    </dict>
    </plist>
  PLIST

  File.write(plist_path, content)
  log("Created Info.plist at #{plist_path}")
end

def create_scheme(project, target, flavor)
  require 'xcodeproj/scheme'
  scheme_name = flavor
  scheme_dir = Xcodeproj::XCScheme.shared_data_dir(project.path)
  FileUtils.mkdir_p(scheme_dir)
  scheme_path = File.join(scheme_dir, "#{scheme_name}.xcscheme")

  scheme = Xcodeproj::XCScheme.new
  scheme.add_build_target(target)

  scheme.test_action.build_configuration = "Debug-#{flavor}"
  scheme.launch_action.build_configuration = "Debug-#{flavor}"
  scheme.profile_action.build_configuration = "Release-#{flavor}"
  scheme.analyze_action.build_configuration = "Debug-#{flavor}"
  scheme.archive_action.build_configuration = "Release-#{flavor}"

  scheme.save_as(project.path, scheme_name, true)
  log("Created scheme: #{scheme_name}")
end

flavor_configs.each do |entry|
  flavor = entry['flavor']
  ios_config = entry['iOS'] || {}
  bundle_id_suffix = ios_config['bundleIdSuffix'] || ".#{flavor}"
  display_name_suffix = ios_config['displayNameSuffix'] || " #{flavor.capitalize}"

  plist_path = "Runner/flavors/#{flavor}/Info.plist"
  bundle_id = "#{BASE_BUNDLE_ID}#{bundle_id_suffix}"
  app_name = "MyApp#{display_name_suffix}"

  create_flavor_plist(flavor, bundle_id, File.join(project_root, 'ios', plist_path), app_name)

  runner_target.build_configuration_list.build_configurations.each do |base_config|
    next if base_config.name.include?('-')
    add_flavor_build_config(project, runner_target, base_config, flavor, bundle_id_suffix, plist_path)
  end

  create_scheme(project, runner_target, flavor)
end

project.save
log("✅ Flavors successfully configured. Check Xcode schemes and build configurations!")
puts "[INFO] Restore from backup if needed: #{backup_path}"
