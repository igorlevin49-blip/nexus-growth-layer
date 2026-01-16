
-- Backfill missing L3/L4 commissions for Диас Бауржан
-- Total: 11 commissions × 5,500 ₸ = 60,500 ₸
-- source_ref format: subscription_{subscription_id}_s1_level_{level}

DO $$
DECLARE
  v_sponsor_id UUID := '975d28e6-ce75-452c-871c-29e12183ccf2';
  v_commission_amount INTEGER := 5500;
  v_freeze_days INTEGER := 14;
  v_created_count INTEGER := 0;
  
  v_l3_partners UUID[] := ARRAY[
    '5d0f329e-c4f2-4ceb-a6b3-981129da5a7e'::UUID,
    '029f5722-561f-406d-94b4-55fcbf57ecd1'::UUID,
    '920dcab0-bcbd-4bbf-9fc5-f939e84e1e62'::UUID,
    '68a14133-00a7-474f-8c7f-ce2881eaac49'::UUID,
    '5af17977-df10-41c4-8f8b-2749e65793e0'::UUID,
    '372a4d21-a9be-4a2a-adad-aa024e75109f'::UUID,
    '1fc8cc12-16f8-4238-96cd-5eec78a5cb91'::UUID
  ];
  
  v_l4_partners UUID[] := ARRAY[
    '404e23ff-1b43-46a2-84f9-dee9b848cfc4'::UUID,
    'f4c8fbbb-5f71-4c0d-ac0c-acd7d5ec3bb1'::UUID,
    '26746be1-81e7-4335-a463-92bcf39e9271'::UUID,
    'dfafee5f-690a-42ed-9b04-7739f8844a46'::UUID
  ];
  
  v_partner_id UUID;
  v_subscription_id UUID;
  v_paid_at TIMESTAMPTZ;
  v_frozen_until TIMESTAMPTZ;
  v_existing_count INTEGER;
  v_status public.transaction_status;
  v_source_ref TEXT;
BEGIN
  FOREACH v_partner_id IN ARRAY v_l3_partners LOOP
    SELECT id, paid_at INTO v_subscription_id, v_paid_at
    FROM subscriptions
    WHERE user_id = v_partner_id AND status = 'active' AND paid_at IS NOT NULL
    ORDER BY paid_at DESC LIMIT 1;
    
    IF v_subscription_id IS NOT NULL THEN
      v_source_ref := 'subscription_' || v_subscription_id || '_s1_level_3';
      
      SELECT COUNT(*) INTO v_existing_count
      FROM transactions WHERE user_id = v_sponsor_id AND source_ref = v_source_ref;
      
      IF v_existing_count = 0 THEN
        v_frozen_until := v_paid_at + (v_freeze_days || ' days')::INTERVAL;
        v_status := CASE WHEN v_frozen_until > NOW() THEN 'frozen'::public.transaction_status ELSE 'completed'::public.transaction_status END;
        
        INSERT INTO transactions (user_id, type, amount_cents, currency, status, source_id, source_ref, level, structure_type, frozen_until, payload, created_at)
        VALUES (v_sponsor_id, 'commission', v_commission_amount, 'KZT', v_status, v_subscription_id, v_source_ref, 3, 'primary'::public.structure_type, v_frozen_until,
          jsonb_build_object('subscriber_id', v_partner_id, 'backfill', true, 'backfill_date', NOW(), 'backfill_reason', 'L3 backfill'), v_paid_at);
        v_created_count := v_created_count + 1;
        
        IF v_frozen_until <= NOW() THEN
          UPDATE profiles SET balance = COALESCE(balance, 0) + v_commission_amount WHERE id = v_sponsor_id;
        END IF;
      END IF;
    END IF;
  END LOOP;
  
  FOREACH v_partner_id IN ARRAY v_l4_partners LOOP
    SELECT id, paid_at INTO v_subscription_id, v_paid_at
    FROM subscriptions
    WHERE user_id = v_partner_id AND status = 'active' AND paid_at IS NOT NULL
    ORDER BY paid_at DESC LIMIT 1;
    
    IF v_subscription_id IS NOT NULL THEN
      v_source_ref := 'subscription_' || v_subscription_id || '_s1_level_4';
      
      SELECT COUNT(*) INTO v_existing_count
      FROM transactions WHERE user_id = v_sponsor_id AND source_ref = v_source_ref;
      
      IF v_existing_count = 0 THEN
        v_frozen_until := v_paid_at + (v_freeze_days || ' days')::INTERVAL;
        v_status := CASE WHEN v_frozen_until > NOW() THEN 'frozen'::public.transaction_status ELSE 'completed'::public.transaction_status END;
        
        INSERT INTO transactions (user_id, type, amount_cents, currency, status, source_id, source_ref, level, structure_type, frozen_until, payload, created_at)
        VALUES (v_sponsor_id, 'commission', v_commission_amount, 'KZT', v_status, v_subscription_id, v_source_ref, 4, 'primary'::public.structure_type, v_frozen_until,
          jsonb_build_object('subscriber_id', v_partner_id, 'backfill', true, 'backfill_date', NOW(), 'backfill_reason', 'L4 backfill'), v_paid_at);
        v_created_count := v_created_count + 1;
        
        IF v_frozen_until <= NOW() THEN
          UPDATE profiles SET balance = COALESCE(balance, 0) + v_commission_amount WHERE id = v_sponsor_id;
        END IF;
      END IF;
    END IF;
  END LOOP;
  
  RAISE NOTICE 'Created % commissions for Dias Baurzhan', v_created_count;
END $$;
