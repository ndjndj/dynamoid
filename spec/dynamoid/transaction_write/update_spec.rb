# frozen_string_literal: true

require 'spec_helper'
require_relative 'context'

# Dynamoid.config.logger.level = :debug

describe Dynamoid::TransactionWrite, '.update' do
  include_context 'transaction_write'

  context 'updates' do
    context 'simple primary key' do
      before do
        klass.create_table
      end

      it 'with attribute outside transaction' do
        obj1 = klass.create!(name: 'one')
        obj1.name = 'oneone'
        described_class.execute do |txn|
          txn.update! obj1
        end
        obj1_found = klass.find(obj1.id)
        expect(obj1_found).to eql(obj1)
        expect(obj1_found.name).to eql('oneone')
      end

      it 'with attribute in transaction' do
        obj2 = klass.create!(name: 'two')
        described_class.execute do |txn|
          txn.update! obj2,  { name: 'twotwo' }
        end
        obj2_found = klass.find(obj2.id)
        expect(obj2_found).to eql(obj2)
        expect(obj2_found.name).to eql('twotwo')
      end

      it 'with class updates in transaction' do
        obj3 = klass.create!(name: 'three')
        described_class.execute do |txn|
          txn.update! klass, { id: obj3.id, name: 'threethree' }
        end
        obj3_found = klass.find(obj3.id)
        expect(obj3_found).to eql(obj3)
        expect(obj3_found.name).to eql('threethree')
      end
    end

    context 'composite key' do
      before do
        klass_with_composite_key.create_table
      end

      it 'with attribute outside transaction' do
        obj1 = klass_with_composite_key.create!(name: 'one', age: 1)
        obj1.name = 'oneone'
        described_class.execute do |txn|
          txn.update! obj1
        end
        obj1_found = klass_with_composite_key.find(obj1.id, range_key: 1)
        expect(obj1_found).to eql(obj1)
        expect(obj1_found.name).to eql('oneone')
      end

      it 'with attribute in transaction' do
        obj2 = klass_with_composite_key.create!(name: 'two', age: 2)

        described_class.execute do |txn|
          txn.update! obj2, { name: 'twotwo' }
        end
        obj2_found = klass_with_composite_key.find(obj2.id, range_key: 2)
        expect(obj2_found).to eql(obj2)
        expect(obj2_found.name).to eql('twotwo')
      end

      it 'with class updates in transaction' do
        obj3 = klass_with_composite_key.create!(name: 'three', age: 3)
        described_class.execute do |txn|
          txn.update! klass_with_composite_key, { id: obj3.id, age: 3, name: 'threethree' }
        end
        obj3_found = klass_with_composite_key.find(obj3.id, range_key: 3)
        expect(obj3_found).to eql(obj3)
        expect(obj3_found.name).to eql('threethree')
      end
    end

    it 'updates timestamps of instance' do
      klass.create_table
      obj1 = klass.create!(name: 'one', created_at: Time.now - 48.hours, updated_at: Time.now - 24.hours)
      obj1.name = 'oneone'
      described_class.execute do |txn|
        txn.update! obj1
      end
      obj1_found = klass.find(obj1.id)
      expect(obj1_found.created_at.to_f).to be < (Time.now - 47.hours).to_f
      expect(obj1_found.updated_at.to_f).to be_within(1.seconds).of Time.now.to_f
    end

    it 'updates timestamps by class' do
      klass.create_table
      obj3 = klass.create!(name: 'three', created_at: Time.now - 48.hours, updated_at: Time.now - 24.hours)
      described_class.execute do |txn|
        txn.update! klass, { id: obj3.id, name: 'threethree' }
      end
      obj3_found = klass.find(obj3.id)
      expect(obj3_found.created_at.to_f).to be < (Time.now - 47.hours).to_f
      expect(obj3_found.updated_at.to_f).to be_within(1.seconds).of Time.now.to_f
    end

    context 'validates' do
      before do
        klass_with_validation.create_table
      end

      it 'does not update when invalid' do
        obj1 = klass_with_validation.create!(name: 'onelong')
        described_class.execute do |txn|
          obj1.name = 'one'
          expect(txn.update(obj1)).to eql(false)
        end
        obj1_found = klass_with_validation.find(obj1.id)
        expect(obj1_found.name).to eql('onelong')
      end

      it 'allows partial update when a record in the transaction is invalid' do
        obj1 = klass_with_validation.create!(name: 'onelong')
        obj2 = klass_with_validation.create!(name: 'twolong')
        described_class.execute do |txn|
          obj1.name = 'one'
          expect(txn.update(obj1)).to eql(false)
          obj2.name = 'twotwo'
          expect(txn.update(obj2)).to be_truthy
        end
        obj1_found = klass_with_validation.find(obj1.id)
        expect(obj1_found.name).to eql('onelong')
        obj2_found = klass_with_validation.find(obj2.id)
        expect(obj2_found.name).to eql('twotwo')
      end

      it 'succeeds when valid' do
        obj1 = klass_with_validation.create!(name: 'onelong')
        described_class.execute do |txn|
          obj1.name = 'oneone'
          expect(txn.update(obj1)).to be_present
        end

        obj1_found = klass_with_validation.find(obj1.id)
        expect(obj1_found).to eql(obj1)
        expect(obj1_found.name).to eql('oneone')
      end

      it 'raises DocumentNotValid when not valid' do
        obj1 = klass_with_validation.create!(name: 'onelong')
        expect {
          described_class.execute do |txn|
            obj1.name = 'one'
            txn.update! obj1
          end
        }.to raise_error(Dynamoid::Errors::DocumentNotValid)
        obj1_found = klass_with_validation.find(obj1.id)
        expect(obj1_found.name).to eql('onelong')
      end

      it 'rolls back and raises DocumentNotValid when not valid' do
        obj1 = klass_with_validation.create!(name: 'onelong')
        obj2 = klass_with_validation.create!(name: 'twolong')
        expect {
          described_class.execute do |txn|
            obj2.name = 'twotwo'
            txn.update! obj2
            obj1.name = 'one'
            txn.update! obj1
          end
        }.to raise_error(Dynamoid::Errors::DocumentNotValid)
        obj1_found = klass_with_validation.find(obj1.id)
        expect(obj1_found.name).to eql('onelong')
        obj2_found = klass_with_validation.find(obj2.id)
        expect(obj2_found.name).to eql('twolong')
      end

      it 'does not raise exception when valid' do
        obj1 = klass_with_validation.create!(name: 'onelong')
        described_class.execute do |txn|
          obj1.name = 'oneone'
          txn.update! obj1
        end

        obj1_found = klass_with_validation.find(obj1.id)
        expect(obj1_found).to eql(obj1)
        expect(obj1_found.name).to eql('oneone')
      end

      it 'does not raise exception when skipping validation' do
        obj1 = klass_with_validation.create!(name: 'onelong')
        described_class.execute do |txn|
          obj1.name = 'one'
          # this use is infrequent, normal entry is from save!(obj, options)
          txn.update! obj1, {}, { skip_validation: true }
        end

        obj1_found = klass_with_validation.find(obj1.id)
        expect(obj1_found).to eql(obj1)
        expect(obj1_found.name).to eql('one')
      end

      it 'uses callbacks' do
        klass_with_callbacks.create_table
        obj1 = klass_with_callbacks.create!(name: 'one')
        expect {
          described_class.execute do |txn|
            obj1.name = 'oneone'
            txn.update! obj1
          end
        }.to output('validating validated saving updating updated saved ').to_stdout
      end

      it 'uses around callbacks' do
        klass_with_around_callbacks.create_table
        obj1 = klass_with_around_callbacks.create!(name: 'one')
        expect {
          described_class.execute do |txn|
            obj1.name = 'oneone'
            txn.update! obj1
          end
        }.to output('saving updating updated saved ').to_stdout
      end
    end
  end
end
