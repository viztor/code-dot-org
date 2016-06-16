require "csv"

namespace :seed do
  verbose true

  task videos: :environment do
    Video.setup
  end

  STANFORD_HINTS_FILE = 'config/stanford-hints-bestPath1.tsv'
  STANFORD_HINTS_IMPORTED = 'config/scripts/.hints_imported'
  file STANFORD_HINTS_IMPORTED => [STANFORD_HINTS_FILE, :environment] do
    LevelSourceHint.transaction do
      source_name = LevelSourceHint::STANFORD
      hint_index = LevelSourceHint.all.index_by(&:level_source_id)
      level_source_hints = CSV.read(STANFORD_HINTS_FILE, { col_sep: "\t" }).map do |row|
        id = row[0].to_i
        hint = hint_index[id] || LevelSourceHint.new(level_source_id: id)
        hint.assign_attributes(
          hint: row[1],
          status: 'experiment',
          source: source_name
        )
        hint
      end.select(&:changed?)
      LevelSourceHint.import level_source_hints, validate: false,
        on_duplicate_key_update: LevelSourceHint.columns.map(&:name).tap{|x|x.delete('id')}
    end
    touch STANFORD_HINTS_IMPORTED
  end

  task concepts: :environment do
    Concept.setup
  end

  task games: :environment do
    Game.setup
  end

  SCRIPTS_GLOB = Dir.glob('config/scripts/**/*.script').sort.flatten
  SEEDED = 'config/scripts/.seeded'

  file SEEDED => [SCRIPTS_GLOB, :environment].flatten do
    update_scripts
  end

  def update_scripts(opts = {})
    # optionally, only process modified scripts to speed up seed time
    scripts_seeded_mtime = (opts[:incremental] && File.exist?(SEEDED)) ?
      File.mtime(SEEDED) : Time.at(0)
    touch SEEDED # touch seeded "early" to reduce race conditions
    begin
      custom_scripts = SCRIPTS_GLOB.select { |script| File.mtime(script) > scripts_seeded_mtime }
      LevelLoader.update_unplugged if File.mtime('config/locales/unplugged.en.yml') > scripts_seeded_mtime
      _, custom_i18n = Script.setup(custom_scripts)
      Script.update_i18n(custom_i18n)
    rescue
      rm SEEDED # if we failed to do any of that stuff we didn't seed anything, did we
      raise
    end
  end

  SCRIPTS_DEPENDENCIES = [:environment, :concepts, :games, :custom_levels, :dsls]
  task scripts: SCRIPTS_DEPENDENCIES do
    update_scripts(incremental: false)
  end

  task scripts_incremental: SCRIPTS_DEPENDENCIES do
    update_scripts(incremental: true)
  end

  # detect changes to dsldefined level files
  # LevelGroup must be last here so that LevelGroups are seeded after all levels that they can contain
  DSL_TYPES = %w(TextMatch ContractMatch External Match Multi EvaluationMulti LevelGroup)
  DSLS_GLOB = DSL_TYPES.map{|x| Dir.glob("config/scripts/**/*.#{x.underscore}*").sort }.flatten
  file 'config/scripts/.dsls_seeded' => DSLS_GLOB do |t|
    Rake::Task['seed:dsls'].invoke
    touch t.name
  end

  require 'digest'

  # explicit execution of "seed:dsls"
  task dsls: [:environment, :concepts, :games, :custom_levels] do
    DSLDefined.transaction do
      all_levels = DSLDefined.all
      levels = all_levels.index_by(&:name)
      levels_by_hash = all_levels.index_by(&:md5)

      dsls_yml = File.expand_path('config/locales/dsls.en.yml')
      old_i18n_strings = File.exist?(dsls_yml) ? YAML.load_file(dsls_yml) : {}
      i18n_strings = {}

      # Parse each .[dsl] file and setup its model.
      dsls = DSLS_GLOB.map do |filename|
        dsl_class = DSL_TYPES.detect{|type|filename.include?(".#{type.underscore}") }.try(:constantize)
        [filename, dsl_class]
      end
      # Update LevelGroup types separately after all other level types to satisfy ordering dependency.
      dsls.partition do |_, dsl_class|
        dsl_class != LevelGroup
      end.each do |dsls|
        dsls.reject! do |filename, dsl_class|
          str = File.read(filename)
          md5 = Digest::MD5.hexdigest(str)
          idx = levels_by_hash[md5]
          if idx.present?
            i18n_strings.deep_merge!(
              {'en' =>
                { 'data' =>
                  { dsl_class.dsl_class.prefix =>
                    old_i18n_strings
                      .try(:[], 'en')
                      .try(:[], 'data')
                      .try(:[], dsl_class.dsl_class.prefix)
                  }
                }
              }
            )
            true
          end
        end
        dsl_data_i18n = dsls.map do |filename, dsl_class|
          begin
            data, i18n = dsl_class.parse_file(filename)
            [dsl_class, data, i18n]
          rescue Exception
            puts "Error parsing #{filename}"
            raise
          end
        end
        dsl_data = dsl_data_i18n.map do |dsl_class, data, i18n|
          i18n_strings.deep_merge! i18n
          [dsl_class, data]
        end
        dsl_objects = dsl_data.map do |dsl_class, data|
          dsl_class.setup(data, levels)
        end.select(&:changed?)
        dsl_objects.each do |level|
          level.run_callbacks(:validation)
          level.run_callbacks(:save) { level.run_callbacks(:create) }
        end
        DSLDefined.import(
          dsl_objects,
          validate: false,
          on_duplicate_key_update: DSLDefined.columns.map(&:name).tap{|x|x.delete('id')}
        )
      end

      # Rewrite autogenerated 'dsls.en.yml' i18n file with new master-copy English strings
      i18n_warning = "# Autogenerated English-language level-definition locale file. Do not edit by hand or commit to version control.\n"
      File.write(dsls_yml, i18n_warning + i18n_strings.deep_sort.to_yaml(line_width: -1))
    end
  end

  task import_custom_levels: :environment do
    LevelLoader.load_custom_levels
  end

  # Generate the database entry from the custom levels json file
  task custom_levels: :environment do
    LevelLoader.load_custom_levels
  end

  task callouts: :environment do
    Callout.transaction do
      Callout.reset_db
      # TODO: If the id of the callout is important, specify it in the tsv
      # preferably the id of the callout is not important ;)
      Callout.find_or_create_all_from_tsv!('config/callouts.tsv')
    end
  end

  task school_districts: :environment do
    SchoolDistrict.transaction do
      # Since other models (e.g. Pd::Enrollment) have a foreign key dependency
      # on SchoolDistrict, don't reset_db first.  (Callout, above, does that.)
      SchoolDistrict.find_or_create_all_from_tsv!('config/school_districts.tsv')
    end
  end

  task trophies: :environment do
    # code in user.rb assumes that broze id: 1, silver id: 2 and gold id: 3.
    Trophy.transaction do
      Trophy.reset_db
      %w(Bronze Silver Gold).each_with_index do |trophy, id|
        Trophy.create!(id: id + 1, name: trophy, image_name: "#{trophy.downcase}trophy.png")
      end
    end
  end

  task prize_providers: :environment do
    PrizeProvider.transaction do
      PrizeProvider.reset_db
      # placeholder data - id's are assumed to start at 1 so prizes below can be loaded properly
      [{name: 'Apple iTunes', description_token: 'apple_itunes', url: 'http://www.apple.com/itunes/', image_name: 'itunes_card.jpg'},
      {name: 'Dropbox', description_token: 'dropbox', url: 'http://www.dropbox.com/', image_name: 'dropbox_card.jpg'},
      {name: 'Valve Portal', description_token: 'valve', url: 'http://www.valvesoftware.com/games/portal.html', image_name: 'portal2_card.png'},
      {name: 'EA Origin Bejeweled 3', description_token: 'ea_bejeweled', url: 'https://www.origin.com/en-us/store/buy/181609/mac-pc-download/base-game/standard-edition-ANW.html', image_name: 'bejeweled_card.jpg'},
      {name: 'EA Origin FIFA Soccer 13', description_token: 'ea_fifa', url: 'https://www.origin.com/en-us/store/buy/fifa-2013/pc-download/base-game/standard-edition-ANW.html', image_name: 'fifa_card.jpg'},
      {name: 'EA Origin SimCity 4 Deluxe', description_token: 'ea_simcity', url: 'https://www.origin.com/en-us/store/buy/sim-city-4/pc-download/base-game/deluxe-edition-ANW.html', image_name: 'simcity_card.jpg'},
      {name: 'EA Origin Plants vs. Zombies', description_token: 'ea_pvz', url: 'https://www.origin.com/en-us/store/buy/plants-vs-zombies/mac-pc-download/base-game/standard-edition-ANW.html', image_name: 'pvz_card.jpg'},
      {name: 'DonorsChoose.org $750', description_token: 'donors_choose', url: 'http://www.donorschoose.org/', image_name: 'donorschoose_card.jpg'},
      {name: 'DonorsChoose.org $250', description_token: 'donors_choose_bonus', url: 'http://www.donorschoose.org/', image_name: 'donorschoose_card.jpg'},
      {name: 'Skype', description_token: 'skype', url: 'http://www.skype.com/', image_name: 'skype_card.jpg'}].each_with_index do |pp, id|
        PrizeProvider.create!(pp.merge!({:id=>id + 1}))
      end
    end
  end

  MAX_LEVEL_SOURCES = 10_000
  desc "calculate solutions (ideal_level_source) for levels based on most popular correct solutions (very slow)"
  task ideal_solutions: :environment do
    require 'benchmark'
    Level.where_we_want_to_calculate_ideal_level_source.each do |level|
      next if level.try(:free_play?)
      puts "Level #{level.id}"
      level_sources_count = level.level_sources.count
      if level_sources_count > MAX_LEVEL_SOURCES
        puts "...skipped, too many possible solutions"
      else
        times = Benchmark.measure { level.calculate_ideal_level_source_id }
        puts "... analyzed #{level_sources_count} in #{times.real.round(2)}s"
      end
    end
  end

  task dummy_prizes: :environment do
    # placeholder data
    Prize.connection.execute('truncate table prizes')
    TeacherPrize.connection.execute('truncate table teacher_prizes')
    TeacherBonusPrize.connection.execute('truncate table teacher_bonus_prizes')
    10.times do |n|
      string = n.to_s
      Prize.create!(prize_provider_id: 1, code: "APPL-EITU-NES0-000" + string)
      Prize.create!(prize_provider_id: 2, code: "DROP-BOX0-000" + string)
      Prize.create!(prize_provider_id: 3, code: "VALV-EPOR-TAL0-000" + string)
      Prize.create!(prize_provider_id: 4, code: "EAOR-IGIN-BEJE-000" + string)
      Prize.create!(prize_provider_id: 5, code: "EAOR-IGIN-FIFA-000" + string)
      Prize.create!(prize_provider_id: 6, code: "EAOR-IGIN-SIMC-000" + string)
      Prize.create!(prize_provider_id: 7, code: "EAOR-IGIN-PVSZ-000" + string)
      TeacherPrize.create!(prize_provider_id: 8, code: "DONO-RSCH-OOSE-750" + string)
      TeacherBonusPrize.create!(prize_provider_id: 9, code: "DONO-RSCH-OOSE-250" + string)
      Prize.create!(prize_provider_id: 10, code: "SKYP-ECRE-DIT0-000" + string)
    end
  end

  task :import_users, [:file] => :environment do |_t, args|
    CSV.read(args[:file], { col_sep: "\t", headers: true }).each do |row|
      User.create!(
          provider: User::PROVIDER_MANUAL,
          name: row['Name'],
          username: row['Username'],
          password: row['Password'],
          password_confirmation: row['Password'],
          birthday: row['Birthday'].blank? ? nil : Date.parse(row['Birthday']))
    end
  end

  def import_prize_from_text(file, provider_id, col_sep)
    Rails.logger.info "Importing prize codes from: " + file + " for provider id " + provider_id.to_s
    CSV.read(file, { col_sep: col_sep, headers: false }).each do |row|
      if row[0].present?
        Prize.create!(prize_provider_id: provider_id, code: row[0])
      end
    end
  end

  task :import_itunes, [:file] => :environment do |_t, args|
    import_prize_from_text(args[:file], 1, "\t")
  end

  task :import_dropbox, [:file] => :environment do |_t, args|
    import_prize_from_text(args[:file], 2, "\t")
  end

  task :import_valve, [:file] => :environment do |_t, args|
    import_prize_from_text(args[:file], 3, "\t")
  end

  task :import_ea_bejeweled, [:file] => :environment do |_t, args|
    import_prize_from_text(args[:file], 4, "\t")
  end

  task :import_ea_fifa, [:file] => :environment do |_t, args|
    import_prize_from_text(args[:file], 5, "\t")
  end

  task :import_ea_simcity, [:file] => :environment do |_t, args|
    import_prize_from_text(args[:file], 6, "\t")
  end

  task :import_ea_pvz, [:file] => :environment do |_t, args|
    import_prize_from_text(args[:file], 7, "\t")
  end

  task :import_skype, [:file] => :environment do |_t, args|
    import_prize_from_text(args[:file], 10, ",")
  end

  task :import_donorschoose_750, [:file] => :environment do |_t, args|
    Rails.logger.info "Importing teacher prize codes from: " + args[:file] + " for provider id 8"
    CSV.read(args[:file], { col_sep: ",", headers: true }).each do |row|
      if row['Gift Code'].present?
        TeacherPrize.create!(prize_provider_id: 8, code: row['Gift Code'])
      end
    end
  end

  task :import_donorschoose_250, [:file] => :environment do |_t, args|
    Rails.logger.info "Importing teacher bonus prize codes from: " + args[:file] + " for provider id 9"
    CSV.read(args[:file], { col_sep: ",", headers: true }).each do |row|
      if row['Gift Code'].present?
        TeacherBonusPrize.create!(prize_provider_id: 9, code: row['Gift Code'])
      end
    end
  end

  task secret_words: :environment do
    SecretWord.setup
  end

  task secret_pictures: :environment do
    SecretPicture.setup
  end

  desc "seed all dashboard data"
  task all: [:videos, :concepts, :scripts, :trophies, :prize_providers, :callouts, :school_districts, STANFORD_HINTS_IMPORTED, :secret_words, :secret_pictures]
  desc "seed all dashboard data that has changed since last seed"
  task incremental: [:videos, :concepts, :scripts_incremental, :trophies, :prize_providers, :callouts, :school_districts, STANFORD_HINTS_IMPORTED, :secret_words, :secret_pictures]

  desc "seed only dashboard data required for tests"
  task test: [:videos, :games, :concepts, :trophies, :prize_providers, :secret_words, :secret_pictures]
end
