# frozen_string_literal: true

module Terminus
  module Repositories
    # The playlist repository.
    class Playlist < DB::Repository[:playlist]
      commands :create, delete: :by_pk

      commands update: :by_pk,
               use: :timestamps,
               plugins_options: {timestamps: {timestamps: :updated_at}}

      def all
        with_current_item.order { created_at.asc }
                         .to_a
      end

      def create_with_items attributes, collection
        transaction do
          record = create attributes
          items = create_items record, collection

          collection.any? ? update(record.id, current_item_id: items.first.id) : record
        end
      end

      def find(id) = (with_current_item.by_pk(id).one if id)

      def find_by(**) = with_current_item.where(**).one

      def auto_update_current_item record, item_id
        return record unless record.automatic?

        update record.id, current_item_id: item_id
      end

      def search key, value
        playlist.where(Sequel.ilike(key, "%#{value}%"))
                .order { created_at.asc }
                .to_a
      end

      def update_current_item id, item
        record = find id
        record && item ? update(id, current_item_id: item.id) : record
      end

      def update_with_items id, attributes, collection
        transaction do
          record = update id, attributes

          playlist_item.where(playlist_id: id).command(:delete).call if collection
          create_items record, collection if collection
          record
        end
      end

      def where(**)
        playlist.where(**)
                .order { created_at.asc }
                .to_a
      end

      def with_items = with_current_item.combine :playlist_items

      def with_screens = with_current_item.combine :screens

      private

      def with_current_item = playlist.combine current_item: :screen

      def create_items playlist, collection
        id = playlist.id

        collection.map.with_index 1 do |item, position|
          playlist_item.command(:create).call playlist_id: id,
                                              screen_id: item[:screen_id],
                                              position:
        end
      end
    end
  end
end
