
-- Add missing commissions for Коханова Елена
-- Frozen commissions are tracked in transactions table with status='frozen'

DO $$
DECLARE
  v_elena_id UUID;
  v_isakova_id UUID;
  v_lidiya_id UUID;
  v_isakova_sub_id UUID;
  v_lidiya_sub_id UUID;
  v_commission_cents BIGINT := 550000; -- 5500 KZT in cents (55000 * 0.10 * 100)
  v_existing_commission UUID;
BEGIN
  -- Get Елена Коханова's ID
  SELECT id INTO v_elena_id
  FROM profiles
  WHERE email = 'elena.atomy.stars@gmail.com';

  IF v_elena_id IS NULL THEN
    RAISE NOTICE 'Elena not found';
    RETURN;
  END IF;

  -- Get Исакова Галина's info
  SELECT p.id, s.id INTO v_isakova_id, v_isakova_sub_id
  FROM profiles p
  LEFT JOIN subscriptions s ON s.user_id = p.id AND s.status = 'active'
  WHERE p.sponsor_id = v_elena_id
    AND p.full_name ILIKE '%Исакова%';

  -- Get Лидия Евгеньевна's info
  SELECT p.id, s.id INTO v_lidiya_id, v_lidiya_sub_id
  FROM profiles p
  LEFT JOIN subscriptions s ON s.user_id = p.id AND s.status = 'active'
  WHERE p.sponsor_id = v_elena_id
    AND p.full_name ILIKE '%Лидия%';

  -- Add commission from Исакова if not exists
  IF v_isakova_id IS NOT NULL AND v_isakova_sub_id IS NOT NULL THEN
    SELECT id INTO v_existing_commission
    FROM transactions
    WHERE user_id = v_elena_id
      AND source_id = v_isakova_id
      AND type = 'commission'
      AND structure_type = 'primary';

    IF v_existing_commission IS NULL THEN
      INSERT INTO transactions (
        user_id, type, amount_cents, currency, status,
        source_id, source_ref, level, structure_type, payload
      ) VALUES (
        v_elena_id, 'commission', v_commission_cents, 'KZT', 'frozen',
        v_isakova_id, v_isakova_sub_id::TEXT, 1, 'primary',
        jsonb_build_object('subscription_amount', 55000, 'commission_rate', 0.10, 'backfill', true)
      );

      RAISE NOTICE 'Added frozen commission from Isakova: 5500 KZT';
    ELSE
      RAISE NOTICE 'Commission from Isakova already exists';
    END IF;
  ELSE
    RAISE NOTICE 'Isakova not found or no active subscription';
  END IF;

  -- Add commission from Лидия if not exists
  IF v_lidiya_id IS NOT NULL AND v_lidiya_sub_id IS NOT NULL THEN
    SELECT id INTO v_existing_commission
    FROM transactions
    WHERE user_id = v_elena_id
      AND source_id = v_lidiya_id
      AND type = 'commission'
      AND structure_type = 'primary';

    IF v_existing_commission IS NULL THEN
      INSERT INTO transactions (
        user_id, type, amount_cents, currency, status,
        source_id, source_ref, level, structure_type, payload
      ) VALUES (
        v_elena_id, 'commission', v_commission_cents, 'KZT', 'frozen',
        v_lidiya_id, v_lidiya_sub_id::TEXT, 1, 'primary',
        jsonb_build_object('subscription_amount', 55000, 'commission_rate', 0.10, 'backfill', true)
      );

      RAISE NOTICE 'Added frozen commission from Lidiya: 5500 KZT';
    ELSE
      RAISE NOTICE 'Commission from Lidiya already exists';
    END IF;
  ELSE
    RAISE NOTICE 'Lidiya not found or no active subscription';
  END IF;
END $$;
