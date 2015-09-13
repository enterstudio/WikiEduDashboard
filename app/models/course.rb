# == Schema Information
#
# Table name: courses
#
#  id                :integer          not null, primary key
#  title             :string(255)
#  created_at        :datetime
#  updated_at        :datetime
#  start             :date
#  end               :date
#  school            :string(255)
#  term              :string(255)
#  character_sum     :integer          default(0)
#  view_sum          :integer          default(0)
#  user_count        :integer          default(0)
#  article_count     :integer          default(0)
#  revision_count    :integer          default(0)
#  slug              :string(255)
#  listed            :boolean          default(TRUE)
#  trained_count     :integer          default(0)
#  meeting_days      :string(255)
#  signup_token      :string(255)
#  assignment_source :string(255)
#  subject           :string(255)
#  expected_students :integer
#  description       :text
#  submitted         :boolean          default(FALSE)
#  passcode          :string(255)
#  timeline_start    :date
#  timeline_end      :date
#  day_exceptions    :string(255)      default("")
#  weekdays          :string(255)      default("0000000")
#  new_article_count :integer
#

#= Course model
class Course < ActiveRecord::Base
  ######################
  # Users for a course #
  ######################
  has_many :courses_users, class_name: CoursesUsers, dependent: :destroy
  has_many :users, -> { uniq }, through: :courses_users,
                                after_remove: :cleanup_articles
  has_many :students, -> { where('courses_users.role = 0') },
           through: :courses_users, source: :user
  has_many :instructors, -> { where('courses_users.role = 1') },
           through: :courses_users, source: :user
  has_many :volunteers, -> { where('courses_users.role > 1') },
           through: :courses_users, source: :user

  #########################
  # Activity by the users #
  #########################
  has_many :revisions, -> (course) {
    where('date >= ?', course.start).where('date <= ?', course.end)
  }, through: :students
  has_many :uploads, through: :students

  has_many :articles_courses, class_name: ArticlesCourses, dependent: :destroy
  has_many :articles, -> { uniq }, through: :articles_courses

  has_many :assignments, dependent: :destroy

  ############
  # Metadata #
  ############
  has_many :cohorts_courses, class_name: CohortsCourses, dependent: :destroy
  has_many :cohorts, through: :cohorts_courses

  has_many :tags, dependent: :destroy

  # Legacy courses are ones that are imported from the EducationProgram
  # MediaWiki extension, not created within the dashboard via the wizard.
  LEGACY_COURSE_MAX_ID = 9999
  scope :legacy, -> { where('courses.id <= ?', LEGACY_COURSE_MAX_ID) }
  scope :not_legacy, -> { where('courses.id > ?', LEGACY_COURSE_MAX_ID) }

  scope :unsubmitted_listed, -> { where(submitted: false).where(listed: true).merge(Course.not_legacy) }

  scope :listed, -> { where(listed: true) }

  ##################
  # Course content #
  ##################
  has_many :weeks, dependent: :destroy
  has_many :blocks, through: :weeks, dependent: :destroy
  has_many :gradeables, as: :gradeable_item, dependent: :destroy

  scope :current, lambda {
    current_and_future.where('start < ?', Time.now)
  }
  # A course stays "current" for a while after the end date, during which time
  # we still check for new data and update page views.
  scope :current_and_future, lambda {
    update_length = Figaro.env.update_length.to_i.days.seconds.to_i
    where('end > ?', Time.now - update_length)
  }

  before_save :order_weeks
  validates :passcode, presence: true, unless: :is_legacy_course?

  def self.submitted_listed
    Course.includes(:cohorts).where('cohorts.id IS NULL')
      .where(listed: true).where(submitted: true)
      .references(:cohorts)
  end

  def self.generate_passcode
    ('a'..'z').to_a.sample(8).join
  end

  ####################
  # Instance methods #
  ####################
  def to_param
    # This method is used by ActiveRecord
    slug
  end

  def legacy?
    id <= LEGACY_COURSE_MAX_ID
  end

  def wiki_title
    # Legacy courses using the EducationProgram extension have ids under 10000.
    prefix = legacy? ? 'Education_Program:' : Figaro.env.course_prefix + '/'
    escaped_slug = slug.gsub(' ', '_')
    "#{prefix}#{escaped_slug}"
  end

  def url
    language = Figaro.env.wiki_language
    "https://#{language}.wikipedia.org/wiki/#{wiki_title}"
  end

  def delist
    self.listed = false
    save
  end

  def update(data={}, should_save=true)
    if legacy?
      require "#{Rails.root}/lib/course_update_manager"
      CourseUpdateManager.update_from_wiki(self, data, should_save)
    else
      self.attributes = data[:course]
      save if should_save
    end
  end

  def students_without_instructor_students
    students.where.not(id: instructors.pluck(:id))
  end

  #################
  # Cache methods #
  #################
  def character_sum
    update_cache unless self[:character_sum]
    self[:character_sum]
  end

  def view_sum
    update_cache unless self[:view_sum]
    self[:view_sum]
  end

  def user_count
    self[:user_count] || students_without_instructor_students.size
  end

  def trained_count
    update_cache unless self[:trained_count]
    self[:trained_count]
  end

  def revision_count
    self[:revision_count] || revisions.size
  end

  def article_count
    self[:article_count] || articles.namespace(0).live.size
  end

  def new_article_count
    self[:new_article_count] || articles_courses.live.new_article
      .joins(:article).where('articles.namespace = 0')
      .size
  end

  def update_cache
    # Do not consider revisions with negative byte changes
    self.character_sum = courses_users.where(role: 0).sum(:character_sum_ms)
    self.view_sum = articles_courses.live.sum(:view_count)
    self.user_count = students_without_instructor_students.size
    self.trained_count = students_without_instructor_students.trained.size
    self.revision_count = revisions.size
    self.article_count = articles.namespace(0).live.size
    self.new_article_count = articles_courses.live.new_article
      .joins(:article).where('articles.namespace = 0')
      .size
    save
  end

  def manual_update
    require "#{Rails.root}/lib/course_update_manager"
    CourseUpdateManager.manual_update self
  end

  ####################
  # Callback methods #
  ####################
  def cleanup_articles(user)
    # find which course articles this user contributed to
    user_articles = user.revisions
                    .where('date >= ? AND date <= ?', start, self.end)
                    .pluck(:article_id)
    course_articles = articles.pluck(:id)
    possible_deletions = course_articles & user_articles

    # have these articles been edited by other students in this course?
    to_delete = []
    possible_deletions.each do |pd|
      other_editors = Article.find(pd).editors - [user.id]
      course_editors = students & other_editors
      to_delete.push pd if other_editors.empty? || course_editors.empty?
    end

    # remove orphaned articles from the course
    articles.delete(Article.find(to_delete))

    # update course cache to account for removed articles
    update_cache unless to_delete.empty?
  end

  #################
  # Class methods #
  #################
  def self.update_all_caches
    Course.transaction do
      Course.current.each(&:update_cache)
    end
  end

  def reorder_weeks
    order_weeks
  end

  private

  def order_weeks
    weeks.each_with_index do |week, i|
      week.update_attribute(:order, i + 1)
    end
  end

  # for use in validation
  def is_legacy_course?
    return true unless Course.any?
    Course.last.id <= LEGACY_COURSE_MAX_ID
  end
end
