#!/usr/bin/env ruby

# iOS Flavor Setup Script for Flutter Projects
# Usage:
#   gem install xcodeproj
#   ruby ios_flavor_setup.rb path/to/flavor_configs.json

puts "[DEBUG] Ruby script loaded from: #{__FILE__}"
gem 'xcodeproj', '= 1.27.0'
require 'json'
require 'xcodeproj'
require 'fileutils'
require 'rexml/document'

BASE_BUNDLE_ID = 'com.example'  # Change this to your actual base ID

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

def duplicate_target(project, base_target, flavor)
  new_target_name = "Runner-#{flavor}"
  puts "[INFO] Duplicating target: #{base_target.name} -> #{new_target_name}"

  new_target = project.new_target(
    base_target.symbol_type,
    new_target_name,
    base_target.platform_name,
    base_target.deployment_target
  )
  new_target.product_name = new_target_name
  new_target.product_type = base_target.product_type

  product_name = "#{new_target_name}.app"
  existing_product = project.products_group.children.find { |child| child.display_name == product_name }
  new_target.product_reference = existing_product || project.products_group.new_file(product_name)

  puts "[INFO] Copying build phases..."
  new_target.build_phases.clear
  base_target.build_phases.each do |base_phase|
    begin
      new_phase = project.new(base_phase.isa)

      new_phase.name = base_phase.name if new_phase.respond_to?(:name=) && base_phase.respond_to?(:name)

      if base_phase.respond_to?(:shell_script) && new_phase.respond_to?(:shell_script=)
        new_phase.shell_script = base_phase.shell_script
      end

      base_phase.files.each do |file|
        new_phase.add_file_reference(file.file_ref, true) if file.file_ref
      end

      new_target.build_phases << new_phase
    rescue => e
      puts "[WARNING] Could not copy phase: #{e.message}"
    end
  end

  puts "[INFO] Copying build configurations..."
  new_target.build_configuration_list.build_configurations.clear
  base_target.build_configurations.each do |config|
    new_config = project.new(Xcodeproj::Project::Object::XCBuildConfiguration)
    new_config.name = config.name
    new_config.build_settings = config.build_settings.dup
    new_target.build_configuration_list.build_configurations << new_config
  end

  puts "[INFO] Copying target dependencies..."
  base_target.dependencies.each do |dep|
    new_target.add_dependency(dep.target) if dep.target
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
  end
end

def create_scheme(project, target, flavor)
  puts "[INFO] Creating scheme for #{flavor}..."

  schemes_dir = Xcodeproj::XCScheme.shared_data_dir(project.path)
  original_scheme_path = File.join(schemes_dir, 'Runner.xcscheme')
  new_scheme_path = File.join(schemes_dir, "#{flavor}.xcscheme")

  unless File.exist?(original_scheme_path)
    raise "Runner.xcscheme not found at #{original_scheme_path}"
  end

  # Copy the original
  FileUtils.cp(original_scheme_path, new_scheme_path)

  # Patch it
  xml = REXML::Document.new(File.read(new_scheme_path))

  xml.elements.each('//BuildableReference') do |node|
    node.attributes['BlueprintIdentifier'] = target.uuid
    node.attributes['BuildableName'] = target.product_reference.path
    node.attributes['BlueprintName'] = target.name
    node.attributes['ReferencedContainer'] = "container:#{project.path.basename}"
  end

  xml.elements.each('//LaunchAction') do |node|
    node.attributes['buildConfiguration'] = "Debug-#{flavor}"
  end
  xml.elements.each('//TestAction') do |node|
    node.attributes['buildConfiguration'] = "Debug-#{flavor}"
  end
  xml.elements.each('//ProfileAction') do |node|
    node.attributes['buildConfiguration'] = "Release-#{flavor}"
  end
  xml.elements.each('//AnalyzeAction') do |node|
    node.attributes['buildConfiguration'] = "Debug-#{flavor}"
  end
  xml.elements.each('//ArchiveAction') do |node|
    node.attributes['buildConfiguration'] = "Release-#{flavor}"
  end

  File.open(new_scheme_path, 'w') { |f| xml.write(f, 2) }

  puts "[INFO] Created duplicated scheme at #{new_scheme_path}"
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
  if File.exist?(runner_scheme_path)
    FileUtils.rm(runner_scheme_path)
    puts "\n[INFO] Removed original 'Runner' scheme."
  end

  project.save
  puts "\n✅ [SUCCESS] iOS flavor setup complete!"
  puts "[INFO] If you encounter issues, restore from backup: #{backup_path}"

rescue => e
  puts "\n❌ [ERROR] Script failed: #{e.message}"
  puts "[INFO] Restoring from backup..."
  FileUtils.rm_rf(ios_project_path)
  FileUtils.cp_r(backup_path, ios_project_path)
  puts "[INFO] Backup restored. Please check the error and try again."
  exit 1
end
