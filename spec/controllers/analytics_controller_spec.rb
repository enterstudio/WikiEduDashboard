# frozen_string_literal: true
require 'rails_helper'

describe AnalyticsController do
  before do
    allow(controller).to receive(:current_user).and_return(nil)
    create(:campaign, id: 1, slug: 'first_campaign')
    create(:campaign, id: 2, slug: 'second_campaign')
    create(:course, id: 1, start: 1.year.ago, end: Time.zone.today)
    create(:campaigns_course, course_id: 1, campaign_id: 1)
  end

  describe '#index' do
    it 'renders' do
      get 'index'
      expect(response.status).to eq(200)
    end
  end

  describe '#results' do
    it 'returns a monthly report' do
      post 'results', params: { monthly_report: true }
      expect(response.status).to eq(200)
    end

    it 'returns campaign statistics' do
      post 'results', params: { campaign_stats: true }
      expect(response.status).to eq(200)
    end

    it 'return campaign intersection statistics' do
      post 'results', params: { campaign_intersection: true,
                                campaign_1: { id: 1 },
                                campaign_2: { id: 2 } }
      expect(response.status).to eq(200)
    end
  end
end
