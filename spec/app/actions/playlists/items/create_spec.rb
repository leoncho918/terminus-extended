# frozen_string_literal: true

require "hanami_helper"

RSpec.describe Terminus::Actions::Playlists::Items::Create, :db do
  subject(:action) { described_class.new }

  describe "#call" do
    let(:playlist) { Factory[:playlist] }
    let(:screen) { Factory[:screen, :with_image] }
    let(:playlist_repository) { Terminus::Repositories::Playlist.new }
    let(:screen_repository) { Terminus::Repositories::Screen.new }

    let :params do
      {
        playlist_id: playlist.id,
        playlist_item: {
          screen_id: screen.id
        }
      }
    end

    it "updates playlist with created item when there is no current item" do
      playlist_repository
      Rack::MockRequest.new(action).post("", params: params)

      expect(playlist_repository.find(playlist.id)).to have_attributes(
        current_item_id: kind_of(Integer)
      )
    end

    it "fails as unprocessable entity when parameters are invalid" do
      playlist_repository
      params.delete :playlist_item
      response = Rack::MockRequest.new(action).post("", params: params)

      expect(response.status).to eq(422)
    end

    it "re-renders the form when the selected screen was deleted and rebuilt" do
      deleted = Factory[:screen, :with_image, name: "extension-test", label: "Extension Test"]
      screen_repository.delete(deleted.id)
      replacement = Factory[:screen, :with_image, name: "extension-test", label: "Extension Test"]

      response = Rack::MockRequest.new(action).post(
        "",
        params: {
          playlist_id: playlist.id,
          playlist_item: {
            screen_id: deleted.id
          }
        }
      )

      expect(response.status).to eq(200)
      expect(response.body).to include("no longer exists. Please reselect it.")
      expect(response.body).to include(%(value="#{replacement.id}"))
    end
  end
end
