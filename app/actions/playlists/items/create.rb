# frozen_string_literal: true

module Terminus
  module Actions
    module Playlists
      module Items
        # The create action.
        class Create < Action
          include Deps[
            repository: "repositories.playlist_item",
            playlist_repository: "repositories.playlist",
            screen_repository: "repositories.screen",
            new_view: "views.playlists.items.new",
            show_view: "views.playlists.items.show"
          ]

          params do
            required(:playlist_id).filled :integer
            required(:playlist_item).hash { required(:screen_id).filled :integer }
          end

          def handle request, response
            parameters = request.params
            playlist = playlist_repository.find parameters[:playlist_id]

            halt :unprocessable_content unless parameters.valid? && playlist

            unless screen? parameters
              error playlist, parameters, response
              return
            end

            response.render show_view, item: create(playlist, parameters), layout: false
          end

          private

          def create playlist, parameters
            item = repository.create_with_position playlist_id: playlist.id,
                                                   **parameters[:playlist_item]

            playlist_repository.update_current_item playlist, item
            item
          end

          def error playlist, parameters, response
            response.render new_view,
                            playlist: playlist,
                            screen_options: screen_options,
                            fields: parameters[:playlist_item],
                            errors: build_errors,
                            layout: false
          end

          def build_errors
            {screen_id: ["no longer exists. Please reselect it."]}
          end

          def screen? parameters
            screen_repository.find(parameters.dig(:playlist_item, :screen_id))
          end

          def screen_options prompt: "Select..."
            screens = screen_repository.all
            initial = prompt && screens.any? ? [[prompt, nil]] : []

            screens.reduce(initial) { |all, screen| all.append [screen.label, screen.id] }
          end
        end
      end
    end
  end
end
