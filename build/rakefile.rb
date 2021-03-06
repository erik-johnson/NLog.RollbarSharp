require 'rubygems'
require 'albacore'
require 'version_bumper'

APPLICATION_NAME = "NLog.RollbarSharp"
BUILD_CONFIGURATION = "Release"

ROOT = File.expand_path('../../', __FILE__)
SRC_ROOT = File.join(ROOT, 'src')
BUILD_ROOT = File.join(ROOT, 'build')
SOLUTION_FILE = File.join(SRC_ROOT, "NLog.RollbarSharp.sln")
PROJECT_DIR = SRC_ROOT
BIN_DIR = File.join(PROJECT_DIR, "bin/#{BUILD_CONFIGURATION}/")
PUBLISH_DIR = File.join(BUILD_ROOT, 'publish')
CHANGELOG_FILE = File.join(ROOT, 'CHANGELOG.md')

BUILD_PROPERTIES = {
  :configuration => BUILD_CONFIGURATION
}

bumper_file File.join(ROOT, 'VERSION')

def current_build_number
  bumper_version.to_s
end

def packagename
  "#{APPLICATION_NAME}-#{current_build_number}.zip"
end

# finds the text of the current changelog notes
# used for populating release notes in nuget
def release_notes
  changelog = File.read(CHANGELOG_FILE)
  match = /#\s+(#{Regexp.quote(current_build_number)})[^\r\n]+[\r\n]+(?<text>[^#\z]+)/.match(changelog)
  return "" if match.nil?
  match[:text].strip
end

task :default => [:fetch_packages, :build]

desc "Update the AssemblyInfo file with the latest version"
assemblyinfo :assemblyinfo  do |asm|
  asm.version = current_build_number
  asm.product_name = APPLICATION_NAME
  asm.title = APPLICATION_NAME
  asm.description = APPLICATION_NAME
  asm.output_file =  File.join(PROJECT_DIR, "Properties/AssemblyInfo.cs")
end

desc "Fetch nuget pacakges needed to build the release solution"
exec :fetch_packages do |cmd|
  package_file = File.join(PROJECT_DIR, 'packages.config')
  package_out = File.join(SRC_ROOT, 'packages')

  cmd.command = "nuget"
  cmd.parameters = "install #{package_file} -o #{package_out}"
end

desc "Build the DLLs"
msbuild :build => [:assemblyinfo] do |msb|
  msb.targets :clean, :build
  msb.solution = SOLUTION_FILE
  msb.properties = BUILD_PROPERTIES
  msb.verbosity = "minimal"
end

desc "Create the nuget spec file"
nuspec do |nuspec|

  raise "You haven't updated the changelog with v#{current_build_number} release notes" if release_notes.empty?

  puts "Version #{current_build_number} release_notes\n#{release_notes}"

  nuspec.id = APPLICATION_NAME
  nuspec.version = current_build_number
  nuspec.authors = "Michael Roach"
  nuspec.description = "NLog extension for Rollbar (rollbar.com) error reporting system using RollbarSharp"
  nuspec.release_notes = release_notes
  nuspec.title = APPLICATION_NAME
  nuspec.language = "en-US"
  nuspec.licenseUrl = "https://github.com/mroach/NLog.RollbarSharp/blob/master/LICENSE.txt"
  nuspec.projectUrl = "https://github.com/mroach/NLog.RollbarSharp"
  nuspec.dependency "Newtonsoft.Json", "5.0"
  nuspec.dependency "RollbarSharp", "0.1"
  nuspec.tags = "rollbar rollbarsharp nlog"
  nuspec.working_directory = PUBLISH_DIR
  nuspec.output_file = "#{APPLICATION_NAME}.nuspec"
end

desc "Copy DLLs to the nuget publish directory"
task :copy do
  cp_r(File.join(BIN_DIR, "NLog.RollbarSharp.dll"), File.join(PUBLISH_DIR, 'lib/net40/'))
end

desc "Create the nuget package"
nugetpack do |nuget|
  nuget.command     = "nuget"
  nuget.nuspec      = File.join(PUBLISH_DIR, "#{APPLICATION_NAME}.nuspec")
  nuget.base_folder = PUBLISH_DIR
  nuget.output      = BUILD_ROOT
  nuget.symbols     = false
end

desc "Push nuget package to nuget.org"
nugetpush do |nuget|
  nuget.command     = "nuget"
  nuget.package     = "#{APPLICATION_NAME}.#{current_build_number}.nupkg"
end

desc "Build, generate nuspec, copy DLLs, create nuget package"
task :nugetify => [:build, :nuspec, :copy, :nugetpack]

task :build_changelog do
  # dump the git log. empty lines represent different revisions.
  lines = %x[git log --format=%s -- "#{SRC_ROOT}"].split(/[\r\n]/)

  # include all log entries until we hit one that contains a version note
  new_changes = lines.take_while { |line| !(/Version \d\.\d\.\d\.\d/ =~ line) }

  if new_changes.empty?
    puts "no new changes found"
    next
  end

  heading = "## #{current_build_number} (#{DateTime.now.strftime("%F")})"

  changelog = File.read(CHANGELOG_FILE)

  if !changelog.index("## #{current_build_number}").nil?
    puts "Already contains notes for version #{current_build_number}. You probably want to bump the version."
    next
  end

  puts "Adding #{new_changes.length} items"

  # prepend each commit with an asterisk so it shows up as a list in markdown
  entry = new_changes.map { |line| "* #{line}" }.join("\n").sub("Version #{current_build_number}", "")

  # write new changelog file
  File.open(CHANGELOG_FILE, 'w') do |f|
    f.write "#{heading}\n\n#{entry}\n\n\n"
    f.write changelog
  end
end

