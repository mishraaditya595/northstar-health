#!/usr/bin/env ruby
# frozen_string_literal: true

# Embeds the Apple Watch app in the Flutter Runner project (ADR-0004, ADR-0012).
#
# The watch Swift sources stay in apps/watch_os; the target only references
# them by relative path, so nothing is copied into apps/mobile/ios. The script
# creates the target when it is missing and always syncs it with the disk:
# watch Swift files and the asset catalog that were added are referenced,
# references to deleted files are removed. A second run changes nothing.
# Runner's own files (such as WatchLinkBridge.swift) are never touched.
#
#   cd tool && bundle install && bundle exec ruby embed_watch_target.rb [path/to/Runner.xcodeproj]
#
# No signing identity, team or profile is written: signing stays automatic and
# is supplied by the build (Codemagic integration), never by the repository.

require "xcodeproj"

WATCH_TARGET = "BeyondRepWatch"
WATCH_BUNDLE_ID = "in.beyondrep.app.watchkitapp"
COMPANION_BUNDLE_ID = "in.beyondrep.app"
EMBED_PHASE = "Embed Watch Content"
# Relative to the directory holding Runner.xcodeproj (apps/mobile/ios).
WATCH_ROOT = "../../watch_os"
SOURCE_DIRS = [
  "Sources",
  "Packages/BeyondRepWatchCore/Sources/BeyondRepWatchCore",
].freeze
# Resource folders referenced by the watch target (asset catalog with the icon).
RESOURCE_GLOB = "Sources/**/*.xcassets"

default = File.expand_path("../apps/mobile/ios/Runner.xcodeproj", __dir__)
project_path = File.expand_path(ARGV[0] || default)
project = Xcodeproj::Project.open(project_path)

runner = project.targets.find { |t| t.name == "Runner" } or abort("Runner target not found")
ios_dir = File.dirname(project_path)
# BEYONDREP_WATCH_DIR lets the tests sync against a scratch copy of the sources.
watch_dir = File.expand_path(ENV["BEYONDREP_WATCH_DIR"] || File.expand_path("../apps/watch_os", __dir__))

watch = project.targets.find { |t| t.name == WATCH_TARGET }
created = watch.nil?
if created
  watch = project.new_target(:application, WATCH_TARGET, :watchos, "10.0", nil, :swift)

  # new_target links Foundation through an SDK-versioned path; the SDK links it
  # on its own, and a pinned SDK path would break on another Xcode.
  frameworks = watch.frameworks_build_phase
  frameworks.files.dup.each do |build_file|
    ref = build_file.file_ref
    frameworks.remove_build_file(build_file)
    ref&.remove_from_project
  end
  project.frameworks_group["watchOS"]&.remove_from_project

  # Version numbers follow the iPhone app through Flutter's generated xcconfig.
  # Flutter's Debug/Release xcconfigs also include the CocoaPods settings that
  # link ObjectBox and the plugins, which the watch must not inherit, so the
  # watch gets its own file that includes only Generated.xcconfig.
  watch_xcconfig = File.join(ios_dir, "Flutter", "Watch.xcconfig")
  File.write(watch_xcconfig, "#include \"Generated.xcconfig\"\n") unless File.exist?(watch_xcconfig)
  flutter_group = project.main_group["Flutter"] or abort("Flutter group not found")
  watch_xcconfig_ref = flutter_group.new_reference("Flutter/Watch.xcconfig")
  watch_xcconfig_ref.name = "Watch.xcconfig"
  watch.build_configurations.each { |config| config.base_configuration_reference = watch_xcconfig_ref }
  watch.add_system_library_tbd(["sqlite3"])

  runner.add_dependency(watch)
  phase = runner.new_copy_files_build_phase(EMBED_PHASE)
  phase.dst_subfolder_spec = "16" # Products Directory, with the Watch subfolder
  phase.dst_path = "$(CONTENTS_FOLDER_PATH)/Watch"
  build_file = phase.add_file_reference(watch.product_reference, true)
  build_file.settings = { "ATTRIBUTES" => ["RemoveHeadersOnCopy"] }

  # Flutter's "Thin Binary" script rewrites the app bundle, so a copy phase placed
  # after it forms a dependency cycle with the CocoaPods embed phase. Keep the
  # watch embed directly after "Embed Frameworks", before "Thin Binary".
  runner.build_phases.delete(phase)
  frameworks_index = runner.build_phases.index { |bp| bp.display_name == "Embed Frameworks" }
  abort("Embed Frameworks phase not found") unless frameworks_index
  runner.build_phases.insert(frameworks_index + 1, phase)
end

watch.build_configurations.each do |config|
  config.build_settings.delete("ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME")
  config.build_settings.merge!(
    "PRODUCT_BUNDLE_IDENTIFIER" => WATCH_BUNDLE_ID,
    "PRODUCT_NAME" => "$(TARGET_NAME)",
    "GENERATE_INFOPLIST_FILE" => "YES",
    "INFOPLIST_KEY_CFBundleDisplayName" => "BeyondRep",
    "INFOPLIST_KEY_WKApplication" => "YES",
    "INFOPLIST_KEY_WKCompanionAppBundleIdentifier" => COMPANION_BUNDLE_ID,
    "MARKETING_VERSION" => "$(FLUTTER_BUILD_NAME)",
    "CURRENT_PROJECT_VERSION" => "$(FLUTTER_BUILD_NUMBER)",
    "SWIFT_VERSION" => "5.9",
    "TARGETED_DEVICE_FAMILY" => "4",
    "SKIP_INSTALL" => "YES",
    "CODE_SIGN_STYLE" => "Automatic",
    "ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS" => "NO",
    "ASSETCATALOG_COMPILER_APPICON_NAME" => "AppIcon",
  )
end

# Sync the watch group with the files on disk, as paths relative to watch_dir.
group = project.main_group[WATCH_TARGET] || project.main_group.new_group(WATCH_TARGET, WATCH_ROOT)
swift_files = SOURCE_DIRS.flat_map do |dir|
  files = Dir.glob(File.join(watch_dir, dir, "**", "*.swift")).sort
  abort("no Swift sources under #{dir}") if files.empty?
  files
end.map { |f| f.delete_prefix("#{watch_dir}/") }
resources = Dir.glob(File.join(watch_dir, RESOURCE_GLOB)).sort.map { |f| f.delete_prefix("#{watch_dir}/") }
wanted = swift_files + resources

existing = group.files.to_h { |ref| [ref.path, ref] }
(existing.keys - wanted).each do |path|
  ref = existing[path]
  watch.source_build_phase.remove_file_reference(ref)
  watch.resources_build_phase.remove_file_reference(ref)
  ref.remove_from_project
end
(wanted - existing.keys).each do |path|
  ref = group.new_reference(path)
  if path.end_with?(".swift")
    watch.add_file_references([ref])
  else
    watch.resources_build_phase.add_file_reference(ref)
  end
end

project.save
puts "Embedded #{WATCH_TARGET} in #{project_path}."
