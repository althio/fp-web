# == Schema Information
#
# Table name: snapshots
#
#  id                 :integer          not null, primary key
#  slug               :string(8)        not null
#  user_id            :integer
#  page_id            :integer
#  print_href         :text(65535)
#  min_row            :float(24)
#  max_row            :float(24)
#  min_column         :float(24)
#  max_column         :float(24)
#  min_zoom           :integer
#  max_zoom           :integer
#  description        :text(4294967295)
#  private            :boolean          default(FALSE), not null
#  has_geotiff        :string(3)        default("no")
#  has_geojpeg        :string(3)        default("no")
#  base_url           :string(255)
#  uploaded_file      :string(255)
#  country_name       :string(64)
#  country_woeid      :integer
#  region_name        :string(64)
#  region_woeid       :integer
#  place_name         :string(128)
#  place_woeid        :integer
#  progress           :float(24)
#  created_at         :datetime
#  updated_at         :datetime
#  decoded_at         :datetime
#  scene_file_name    :string(255)
#  scene_content_type :string(255)
#  scene_file_size    :integer
#  scene_updated_at   :datetime
#  s3_scene_url       :string(255)
#  west               :float(24)
#  south              :float(24)
#  east               :float(24)
#  north              :float(24)
#  zoom               :integer
#  geotiff_url        :string(255)
#  failed_at          :datetime
#

class Snapshot < ActiveRecord::Base
  include FriendlyId

  # Environment-specific direct upload url verifier screens for malicious posted upload locations.
  S3_UPLOAD_URL_FORMAT = %r{\Ahttps:\/\/s3\.amazonaws\.com\/#{Rails.application.secrets.aws["s3_bucket_name"]}\/(?<path>uploads\/.+\/(?<filename>.+))\z}.freeze

  # friendly_id configuration

  friendly_id :random_id, use: :slugged

  # kaminari (pagination) configuration

  paginates_per 50

  # paperclip (attachment) configuration

  has_attached_file :scene

  # callbacks
  after_commit :process_scene, on: :create
  after_initialize :apply_defaults

  # validations

  validates :s3_scene_url, presence: true, format: { with: S3_UPLOAD_URL_FORMAT }

  # relations

  belongs_to :uploader,
    class_name: "User",
    foreign_key: :user_id

  belongs_to :page
  has_one :atlas, through: :page

  # scopes

  default_scope {
    includes([:atlas, :page, :uploader])
      .joins(:atlas)
      .where("#{self.table_name}.page_id IS NOT NULL")
      .where("#{self.table_name}.private = false")
      .where("#{Atlas.table_name}.private = false")
      .where("#{self.table_name}.failed_at IS NULL")
      .order("#{self.table_name}.created_at DESC")
  }

  scope :date,
    -> date {
      where("DATE(#{self.table_name}.created_at) = ?", date)
    }

  scope :month,
    -> month {
      where("CONCAT(YEAR(#{self.table_name}.created_at), '-', LPAD(MONTH(#{self.table_name}.created_at), 2, '0')) = ?", month)
    }

  scope :place,
    -> place {
      where("place_woeid = ? OR region_woeid = ? OR country_woeid = ?", place, place, place)
    }

  scope :user,
    -> user {
      where(user_id: user)
    }

  # validations

  validates_attachment_content_type :scene, :content_type => /\Aimage/

  # instance methods

  def title
    "Page #{page.page_number} of #{atlas.title}"
  end

  # TODO this should go away if/when migrating to postgres
  def bbox
    [west, south, east, north]
  end

  def latitude
    north + ((south-north)/2)
  end

  def longitude
    west + ((east-west)/2)
  end

  def uploader_name
    uploader && uploader.username || "anonymous"
  end

  def geometry_string
    if !geojpeg_bounds
      return ''
    end

    bds = geojpeg_bounds.split(',')
    if !bds.length === 4
      return ''
    end

    west = bds[1]
    south = bds[0]
    east = bds[3]
    north = bds[2]
    return "POLYGON((%.6f %.6f,%.6f %.6f,%.6f %.6f,%.6f %.6f,%.6f %.6f))" % [west, south, west, north, east, north, east, south, west, south]
  end

  def incomplete?
    decoded_at.nil? && failed_at.nil?
  end

  def failed?
    !failed_at.nil?
  end

  # store an unescaped version of the URL that Amazon returns from direct
  # upload
  def s3_scene_url=(escaped_url)
    write_attribute(:s3_scene_url, (CGI.unescape(escaped_url) rescue nil))
  end

private

  def apply_defaults
    self.progress ||= 0
  end

  def process_scene
    ProcessSceneJob.perform_later(self)
  end

  def random_id
    # use multiple attempts of a lambda for slug candidates

    25.times.map do
      -> {
        rand(2**256).to_s(36).ljust(8,'a')[0..7]
      }
    end
  end
end
