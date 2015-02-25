require "spec_helper"

module VCAP::RestAPI
  describe VCAP::RestAPI::Query, non_transactional: true do
    include VCAP::RestAPI

    class Author < Sequel::Model
      one_to_many :books
    end

    class Book < Sequel::Model
      many_to_one :author
    end

    before do
      a = Author.create(:str_val => "joe;semi")
      a.add_book(Book.create(:str_val => "two;;semis", :num_val => 1))
      a.add_book(Book.create(:str_val => "three;;;semis and one;semi",
                             :num_val => 1))
      a = Author.create(:str_val => "joe/semi")
      a.add_book(Book.create(:str_val => "two;/semis", :num_val => 1))
      a.add_book(Book.create(:str_val => "x;;semis and one;semi",
                             :num_val => 1))
      a.add_book(Book.create(:str_val => "x;;/;;semis and one;semi",
                             :num_val => 2))
      a.add_book(Book.create(:str_val => "x;;;;semis - don't match this",
                             :num_val => 2))
      a.add_book(Book.create(:str_val => "two;/semis", :num_val => 2))
      
      @queryable_attributes = Set.new(%w(str_val author_id book_id num_val))
    end
    
    describe "#filtered_dataset_from_query_params" do
      describe "shared prefix query" do
        it "should return all authors" do
          q = "str_val:joe*"
          ds = Query.filtered_dataset_from_query_params(Author, Author.dataset,
                                                        @queryable_attributes, :q => q)
          expect(ds.count).to eq 2
        end
      end
      
      describe "slash match 1" do
        it "should return the second author" do
          q = "str_val:joe/s*"
          ds = Query.filtered_dataset_from_query_params(Author, Author.dataset,
                                                        @queryable_attributes, :q => q)
          expect(ds.all).to eq [Author[:str_val => "joe/semi"]]
        end
      end

      describe "semicolon match 1" do
        it "should return the first author" do
          q = "str_val:joe;;s*"
          ds = Query.filtered_dataset_from_query_params(Author, Author.dataset,
                                                        @queryable_attributes, :q => q)
          expect(ds.all).to eq [Author[:str_val => "joe;semi"]]
        end
      end

      describe "semicolon match on three;;;semis" do
        it "should return book 1-2" do
          q = "str_val:three;;;;;;semis and one;;s*"
          ds = Query.filtered_dataset_from_query_params(Book, Book.dataset,
                                                        @queryable_attributes, :q => q)
          expected = Book.all.select do |a|
            a.str_val && a.str_val == "three;;;semis and one;semi" && a.num_val == 1
          end
          expect(ds.all).to match_array(expected)
        end
      end

      describe "semicolon match on x;;/" do
        it "should return book 2-2" do
          q = "str_val:x;;;;s*"
          ds = Query.filtered_dataset_from_query_params(Book, Book.dataset,
                                                        @queryable_attributes, :q => q)
          expected = Book.all.select do |a|
            a.str_val && a.str_val == "x;;semis and one;semi" && a.num_val == 1
          end
          #expect(ds.all).to eq [Book[4]]
          expect(ds.all).to match_array(expected)
        end
      end

      describe "match two fields" do
        it "should return book 2-4(6)" do
          q = "str_val:two;;/s*;num_val:2"
          ds = Query.filtered_dataset_from_query_params(Book, Book.dataset,
                                                        @queryable_attributes, :q => q)
          #expect(ds.all).to eq [Book[7]]
          expected = Book.all.select do |a|
            a.str_val && a.str_val == "two;/semis" && a.num_val == 2
          end
          #expect(ds.all).to eq [Book[4]]
          expect(ds.all).to match_array(expected)
        end
      end

    end
  end
end
