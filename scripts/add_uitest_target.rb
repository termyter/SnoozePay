#!/usr/bin/env ruby
# One-shot project surgery: add the SnoozePayUITests UI-testing bundle target,
# wire it to drive the SnoozePay app, register its test file, and emit a SHARED
# "SnoozePay" scheme whose Test action runs BOTH the unit tests and the new UI
# tests. CI calls `xcodebuild test -scheme SnoozePay`, so no workflow change is
# needed — the shared scheme makes the UI tests run automatically.
#
# Idempotent: re-running is a no-op if the target already exists.
require "xcodeproj"

PROJECT_PATH = File.expand_path("../SnoozePay/SnoozePay.xcodeproj", __dir__)
UITEST_NAME  = "SnoozePayUITests"
APP_NAME     = "SnoozePay"
UNIT_NAME    = "SnoozePayTests"

project = Xcodeproj::Project.open(PROJECT_PATH)
app  = project.targets.find { |t| t.name == APP_NAME }  or abort("app target missing")
unit = project.targets.find { |t| t.name == UNIT_NAME } or abort("unit test target missing")

if project.targets.any? { |t| t.name == UITEST_NAME }
  puts "target #{UITEST_NAME} already exists — nothing to do"
  exit 0
end

# Mirror the app's deployment target (lives at project level, ~26.2).
deployment = project.build_configurations.find { |c| c.name == "Debug" }
                    .build_settings["IPHONEOS_DEPLOYMENT_TARGET"] ||
             app.build_configurations.first.build_settings["IPHONEOS_DEPLOYMENT_TARGET"] ||
             "26.2"

uitest = project.new_target(:ui_test_bundle, UITEST_NAME, :ios, deployment)

# Build settings on both configs. CODE_SIGNING_ALLOWED=NO is passed on the CI
# command line, so the team/style here only matter for local signed builds and
# simply mirror the unit-test target.
uitest.build_configurations.each do |config|
  s = config.build_settings
  s["PRODUCT_BUNDLE_IDENTIFIER"]   = "Ivan-Emelyanov.SnoozePayUITests"
  s["PRODUCT_NAME"]                = "$(TARGET_NAME)"
  s["SWIFT_VERSION"]               = "5.0"
  s["IPHONEOS_DEPLOYMENT_TARGET"]  = deployment
  s["GENERATE_INFOPLIST_FILE"]     = "YES"
  s["TEST_TARGET_NAME"]            = APP_NAME
  s["CODE_SIGN_STYLE"]             = "Automatic"
  s["DEVELOPMENT_TEAM"]            = "8ZKDC782V4"
  s["TARGETED_DEVICE_FAMILY"]      = "1,2"
  s["SWIFT_EMIT_LOC_STRINGS"]      = "NO"
  s["CURRENT_PROJECT_VERSION"]     = "1"
  s["MARKETING_VERSION"]           = "1.0"
end

# The UI test bundle launches and drives the app target.
uitest.add_dependency(app)
project.root_object.attributes["TargetAttributes"] ||= {}
project.root_object.attributes["TargetAttributes"][uitest.uuid] =
  { "TestTargetID" => app.uuid }

# Register the test source under a group + the target's Sources phase.
group = project.main_group.find_subpath(UITEST_NAME, true)
group.set_source_tree("SOURCE_ROOT")
group.set_path(UITEST_NAME)
file_ref = group.new_reference("FiringFlowUITests.swift")
uitest.source_build_phase.add_file_reference(file_ref)

# Shared "SnoozePay" scheme: build the app, run BOTH test bundles in Test.
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app)
scheme.add_test_target(unit)
scheme.add_test_target(uitest)
runnable = Xcodeproj::XCScheme::BuildableProductRunnable.new(app, 0)
scheme.launch_action.buildable_product_runnable  = runnable
scheme.profile_action.buildable_product_runnable = runnable
scheme.save_as(PROJECT_PATH, APP_NAME, true)

project.save
puts "added #{UITEST_NAME} (deployment #{deployment}) + shared #{APP_NAME} scheme"
