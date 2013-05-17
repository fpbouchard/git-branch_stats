require "git-branch_stats/version"

require 'linguist'

# ----- Language extractor from excerpts (that are in fact positive diffs) -----
# This is a simple override of linguist's file blob, it is just 'like' the file
# it references, but its contents is only an exceprt of the changed lines
class ExcerptBlob < Linguist::FileBlob
  def initialize(path, excerpt)
    super(path)
    @data = excerpt
    @size = excerpt.bytesize
  end

  def data
    @data
  end

  def size
    @size
  end
end

# Repostiory that calculates sizes for all types (markup AND programming)
# Since this analyzer is for branches, we want to have precise reporting on
# what has been done, not just programming
class AllTypesRepository < Linguist::Repository
  def compute_stats
    return if @computed_stats

    @enum.each do |blob|
      # Skip files that are likely binary
      next if blob.likely_binary?

      # Skip vendored or generated blobs
      next if blob.vendored? || blob.generated? || blob.language.nil?

      @sizes[blob.language.group] += blob.size
    end

    # Compute total size
    @size = @sizes.inject(0) { |s,(_,v)| s + v }

    # Get primary language
    if primary = @sizes.max_by { |(_, size)| size }
      @language = primary[0]
    end

    @computed_stats = true

    nil
  end
end

module Git
  module BranchStats

    def self.extract_language_stats(stats_by_file)
      file_blobs = stats_by_file.select {|numstat| numstat[:additions] > 0}.collect {|numstat| ExcerptBlob.new('./' + numstat[:filename], numstat[:content])}
      linguist = AllTypesRepository.new(file_blobs)
      # Linguist wraps the language in an object, we only want the language name (and why not, sort it by size, descending)
      language_stats = linguist.languages.collect {|language, size| [language.name, size]}.sort_by {|language, size| -size}
      language_stats
    end


    def self.analyze(branch = `git rev-parse --abbrev-ref HEAD`.strip)
      warnings = []
      # Get all commits that are only visible for this HEAD (branch).
      # List commits, without merges, of HEAD, that are not any ref from other branches
      branches = `git branch`.split(/\n/)
      independent_commits_and_emails = if branches.one?
        independent_commits_and_emails = `git log --format="%H,%ae" --no-merges #{branch}`.split(/\n/)
      else
        independent_commits_and_emails = `git log --format="%H,%ae" --no-merges #{branch} --not $(git for-each-ref --format="%(refname)" refs/heads | grep -Fv refs/heads/#{branch})`.split(/\n/)
      end
      independent_commits = independent_commits_and_emails.collect {|c| c.split(',').first}
      emails = independent_commits_and_emails.collect {|c| c.split(',').last}
      emails = emails.uniq

      # Using the list of independent commits, gather stats

      # Start analysis before the last independent commit
      diff_origin = independent_commits.last + "~"
      commit_count = independent_commits.length
      # Fallback if last independent commit is the first commit of the repository
      # NOTE: Running the analyzer on a branch that has independent commits up to the first commit
      # will give weird results since it will omit this first commit in the numstats and language analysis.
      `git rev-parse --verify --quiet #{diff_origin}`
      if $?.to_i > 0
        diff_origin = independent_commits.last

        warnings.push "WARN: Branch has independent commits since the first commit of the repo, stats will be skewed (can't run stats *before* the first commit)"
        # In this case, exclude the last commit (since it won't be included in the stats)
        commit_count = commit_count - 1
      end

      # Numstats (files, +/-)
      numstats = `git diff --numstat #{diff_origin}`.split(/\n/)
      stats_by_file = numstats.collect do |numstat|
        additions, deletions, filename = numstat.split(/\t/)
        {:additions => additions.to_i, :deletions => deletions.to_i, :filename => filename}
      end

      # Extract content from diffs to generate language stats (only consider diffs that contain added/changed stuff)
      stats_by_file.select {|numstat| numstat[:additions] > 0}.each do |numstat|
        # Since first independent commit
        diff = `git diff #{diff_origin} -- #{numstat[:filename]}`
        # Collect lines prefixed with a single +
        new_content = diff.lines.select {|line| line =~ /^\+[^\+]/}.collect {|line| line[1..-1]}.join("\n")
        # Store in the stats for later language analysis
        numstat[:content] = new_content
      end

      # Extract language stats using github's linguist gem
      language_stats = extract_language_stats(stats_by_file)

      # Normalize stats for json REST API
      commit_count = commit_count
      change_count = stats_by_file.length
      total_additions = stats_by_file.inject(0) {|total, numstat| total += numstat[:additions]}
      total_deletions = stats_by_file.inject(0) {|total, numstat| total += numstat[:deletions]}
      {
        :commits => commit_count,
        :additions => total_additions,
        :deletions => total_deletions,
        :files_changed => change_count,
        :language_stats => language_stats,
        :emails => emails,
        :warnings => warnings
      }
    end

  end
end
