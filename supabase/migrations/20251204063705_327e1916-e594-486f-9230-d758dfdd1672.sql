-- Add 'cash' to the payment_method_type enum
ALTER TYPE payment_method_type ADD VALUE IF NOT EXISTS 'cash';