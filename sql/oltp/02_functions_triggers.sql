-- =====================================================================
--  Триггеры целостности и функции информационной системы
--  (реализация видов запросов 1-6 из задания учебной практики)
-- =====================================================================
SET search_path = plant, public;

-- ---------------------------------------------------------------------
-- Служебное: updated_at для инкрементальной выгрузки в DWH (CDC по метке)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION set_updated_at() RETURNS trigger
LANGUAGE plpgsql SET search_path = plant, public AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END $$;

CREATE TRIGGER trg_employees_updated  BEFORE UPDATE ON employees      FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_worker_det_updated BEFORE UPDATE ON worker_details FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_units_updated      BEFORE UPDATE ON units          FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ---------------------------------------------------------------------
-- Бригадир обязан состоять в своей бригаде весь период руководства
-- (декларативно через FK не выражается - нужен триггер)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION check_leader_is_member() RETURNS trigger
LANGUAGE plpgsql SET search_path = plant, public AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM brigade_memberships m
        WHERE m.brigade_id  = NEW.brigade_id
          AND m.employee_id = NEW.employee_id
          AND daterange(m.valid_from, m.valid_to) @> daterange(NEW.valid_from, NEW.valid_to)
    ) THEN
        RAISE EXCEPTION 'Бригадир % не состоит в бригаде % в период [%, %)',
            NEW.employee_id, NEW.brigade_id, NEW.valid_from, coalesce(NEW.valid_to::text, '∞');
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_leader_is_member
    BEFORE INSERT OR UPDATE ON brigade_leaders
    FOR EACH ROW EXECUTE FUNCTION check_leader_is_member();

-- ---------------------------------------------------------------------
-- Запрос 6. Изменение данных рабочего
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION update_worker(
    p_employee_id   integer,
    p_full_name     varchar DEFAULT NULL,
    p_profession_id smallint DEFAULT NULL,
    p_skill_grade   smallint DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql SET search_path = plant, public AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM employees WHERE employee_id = p_employee_id AND staff_category = 'worker') THEN
        RAISE EXCEPTION 'Рабочий с id % не найден', p_employee_id;
    END IF;

    UPDATE employees
    SET full_name     = coalesce(p_full_name, full_name),
        profession_id = coalesce(p_profession_id, profession_id)
    WHERE employee_id = p_employee_id;

    IF p_skill_grade IS NOT NULL THEN
        UPDATE worker_details SET skill_grade = p_skill_grade WHERE employee_id = p_employee_id;
    END IF;
END $$;

-- ---------------------------------------------------------------------
-- Запрос 6. "Удаление" рабочего = увольнение (soft delete).
-- История операций сохраняется: видно, кто собирал изделия в прошлом.
-- Закрываются членство в бригаде и период бригадирства.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION terminate_worker(
    p_employee_id      integer,
    p_termination_date date DEFAULT current_date
) RETURNS void
LANGUAGE plpgsql SET search_path = plant, public AS $$
BEGIN
    UPDATE brigade_leaders
    SET valid_to = p_termination_date
    WHERE employee_id = p_employee_id
      AND (valid_to IS NULL OR valid_to > p_termination_date)
      AND valid_from < p_termination_date;

    UPDATE brigade_memberships
    SET valid_to = p_termination_date
    WHERE employee_id = p_employee_id
      AND (valid_to IS NULL OR valid_to > p_termination_date)
      AND valid_from < p_termination_date;

    UPDATE employees
    SET termination_date = p_termination_date
    WHERE employee_id = p_employee_id AND staff_category = 'worker';

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Рабочий с id % не найден', p_employee_id;
    END IF;
END $$;

-- ---------------------------------------------------------------------
-- Запрос 6. Физическое удаление допустимо только для ошибочно заведённой
-- записи без истории (иначе потеряем прослеживаемость сборки).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION delete_worker(p_employee_id integer) RETURNS void
LANGUAGE plpgsql SET search_path = plant, public AS $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM brigade_memberships m
        JOIN operations o
          ON o.brigade_id = m.brigade_id
         AND o.started_at::date >= m.valid_from
         AND (m.valid_to IS NULL OR o.started_at::date < m.valid_to)
        WHERE m.employee_id = p_employee_id
    ) THEN
        RAISE EXCEPTION 'У рабочего % есть производственная история - используйте terminate_worker()', p_employee_id;
    END IF;

    DELETE FROM brigade_leaders     WHERE employee_id = p_employee_id;
    DELETE FROM brigade_memberships WHERE employee_id = p_employee_id;
    DELETE FROM employees           WHERE employee_id = p_employee_id AND staff_category = 'worker';
END $$;

-- ---------------------------------------------------------------------
-- Запрос 1. Число и перечень изделий по категориям и в целом,
-- собранных цехом / участком / предприятием за период.
-- GROUPING SETS даёт в одном результате строки по моделям,
-- итоги по категориям и общий итог.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION report_units_assembled(
    p_from        date,
    p_to          date,
    p_workshop_id smallint DEFAULT NULL,
    p_section_id  smallint DEFAULT NULL,
    p_category_id smallint DEFAULT NULL
) RETURNS TABLE (
    row_level    text,
    category     varchar,
    model        varchar,
    units_count  bigint
)
LANGUAGE sql STABLE SET search_path = plant, public AS $$
    WITH scope AS (
        SELECT u.unit_id, pc.name AS category, pm.name AS model
        FROM units u
        JOIN product_models pm     ON pm.model_id = u.model_id
        JOIN product_categories pc ON pc.category_id = pm.category_id
        WHERE (u.assembled_at AT TIME ZONE 'Europe/Moscow')::date BETWEEN p_from AND p_to
          AND (p_workshop_id IS NULL OR pm.workshop_id = p_workshop_id)
          AND (p_category_id IS NULL OR pm.category_id = p_category_id)
          AND (p_section_id IS NULL OR EXISTS (
                SELECT 1 FROM operations o
                WHERE o.unit_id = u.unit_id AND o.section_id = p_section_id))
    )
    SELECT CASE GROUPING(category, model)
               WHEN 0 THEN 'модель'
               WHEN 1 THEN 'итого по категории'
               ELSE 'итого'
           END,
           category, model, count(*)
    FROM scope
    GROUP BY GROUPING SETS ((category, model), (category), ())
    ORDER BY GROUPING(category, model), category, model;
$$;

-- ---------------------------------------------------------------------
-- Запрос 2. Перечень и число участков цеха / предприятия и их начальники
-- на дату (LEFT JOIN: вакантная должность видна как NULL).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION report_sections_and_heads(
    p_workshop_id smallint DEFAULT NULL,
    p_on_date     date     DEFAULT current_date
) RETURNS TABLE (
    workshop                 varchar,
    section                  varchar,
    section_head             varchar,
    masters                  text,
    sections_in_workshop     bigint,
    sections_total           bigint
)
LANGUAGE sql STABLE SET search_path = plant, public AS $$
    WITH active AS (
        SELECT ma.*, e.full_name
        FROM management_assignments ma
        JOIN employees e USING (employee_id)
        WHERE daterange(ma.valid_from, ma.valid_to) @> p_on_date
    )
    SELECT w.name,
           s.name,
           h.full_name,
           (SELECT string_agg(m.full_name, ', ' ORDER BY m.full_name)
              FROM active m
             WHERE m.role_code = 'master' AND m.section_id = s.section_id),
           count(*) OVER (PARTITION BY w.workshop_id),
           count(*) OVER ()
    FROM sections s
    JOIN workshops w ON w.workshop_id = s.workshop_id
    LEFT JOIN active h ON h.role_code = 'section_head' AND h.section_id = s.section_id
    WHERE p_workshop_id IS NULL OR s.workshop_id = p_workshop_id
    ORDER BY w.workshop_id, s.section_id;
$$;

-- ---------------------------------------------------------------------
-- Запрос 3. Состав бригад, участвовавших в сборке указанного изделия.
-- Состав берётся на дату выполнения операции, а не "текущий".
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION report_brigades_for_unit(p_serial_no text)
RETURNS TABLE (
    step_no      smallint,
    work         varchar,
    section      varchar,
    brigade      varchar,
    op_date      date,
    worker       varchar,
    profession   varchar,
    is_leader    boolean
)
LANGUAGE sql STABLE SET search_path = plant, public AS $$
    WITH ops AS (
        SELECT DISTINCT ON (o.step_no, o.brigade_id)
               o.step_no, o.brigade_id, o.section_id, rs.work_type_id,
               (o.started_at AT TIME ZONE 'Europe/Moscow')::date AS op_date
        FROM operations o
        JOIN units u        ON u.unit_id = o.unit_id
        JOIN route_steps rs ON rs.model_id = o.model_id AND rs.step_no = o.step_no
        WHERE u.serial_no = p_serial_no
        ORDER BY o.step_no, o.brigade_id, o.attempt_no
    )
    SELECT ops.step_no, wt.name, s.name, b.name, ops.op_date,
           e.full_name, p.name,
           EXISTS (SELECT 1 FROM brigade_leaders bl
                   WHERE bl.brigade_id = b.brigade_id AND bl.employee_id = e.employee_id
                     AND daterange(bl.valid_from, bl.valid_to) @> ops.op_date)
    FROM ops
    JOIN work_types wt          ON wt.work_type_id = ops.work_type_id
    JOIN sections s             ON s.section_id = ops.section_id
    JOIN brigades b             ON b.brigade_id = ops.brigade_id
    JOIN brigade_memberships bm ON bm.brigade_id = b.brigade_id
                               AND daterange(bm.valid_from, bm.valid_to) @> ops.op_date
    JOIN employees e            ON e.employee_id = bm.employee_id
    JOIN professions p          ON p.profession_id = e.profession_id
    ORDER BY ops.step_no, b.name, e.full_name;
$$;

-- ---------------------------------------------------------------------
-- Запрос 4. Состав бригад указанного участка или цеха на дату
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION report_brigade_composition(
    p_workshop_id smallint DEFAULT NULL,
    p_section_id  smallint DEFAULT NULL,
    p_on_date     date     DEFAULT current_date
) RETURNS TABLE (
    workshop      varchar,
    section       varchar,
    brigade       varchar,
    shift         varchar,
    worker        varchar,
    profession    varchar,
    skill_grade   smallint,
    is_leader     boolean,
    tenure_days   integer,
    brigade_size  bigint
)
LANGUAGE sql STABLE SET search_path = plant, public AS $$
    SELECT w.name, s.name, b.name, b.shift,
           e.full_name, p.name, wd.skill_grade,
           (bl.employee_id IS NOT NULL),
           p_on_date - e.hire_date,
           count(*) OVER (PARTITION BY b.brigade_id)
    FROM brigades b
    JOIN sections s             ON s.section_id = b.section_id
    JOIN workshops w            ON w.workshop_id = s.workshop_id
    JOIN brigade_memberships bm ON bm.brigade_id = b.brigade_id
                               AND daterange(bm.valid_from, bm.valid_to) @> p_on_date
    JOIN employees e            ON e.employee_id = bm.employee_id
    JOIN professions p          ON p.profession_id = e.profession_id
    LEFT JOIN worker_details wd ON wd.employee_id = e.employee_id
    LEFT JOIN brigade_leaders bl ON bl.brigade_id = b.brigade_id
                                AND bl.employee_id = e.employee_id
                                AND daterange(bl.valid_from, bl.valid_to) @> p_on_date
    WHERE (p_workshop_id IS NULL OR s.workshop_id = p_workshop_id)
      AND (p_section_id  IS NULL OR s.section_id  = p_section_id)
    ORDER BY s.section_id, b.name, (bl.employee_id IS NULL), e.full_name;
$$;

-- ---------------------------------------------------------------------
-- Запрос 5. Перечень работ, которые проходит изделие:
--   а) нормативный маршрут модели;
--   б) фактическая история конкретного экземпляра (с доработками и испытаниями).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION report_model_route(p_model_code text)
RETURNS TABLE (step_no smallint, work varchar, section varchar, workshop varchar, std_minutes numeric)
LANGUAGE sql STABLE SET search_path = plant, public AS $$
    SELECT rs.step_no, wt.name, s.name, w.name, rs.std_minutes
    FROM route_steps rs
    JOIN product_models pm ON pm.model_id = rs.model_id
    JOIN work_types wt     ON wt.work_type_id = rs.work_type_id
    JOIN sections s        ON s.section_id = rs.section_id
    JOIN workshops w       ON w.workshop_id = s.workshop_id
    WHERE pm.code = p_model_code
    ORDER BY rs.step_no;
$$;

CREATE OR REPLACE FUNCTION report_unit_history(p_serial_no text)
RETURNS TABLE (event_time timestamptz, stage text, place varchar, detail text, result varchar)
LANGUAGE sql STABLE SET search_path = plant, public AS $$
    SELECT o.started_at, 'операция', s.name,
           wt.name || CASE WHEN o.attempt_no > 1 THEN ' (доработка №' || (o.attempt_no - 1) || ')' ELSE '' END,
           o.result
    FROM operations o
    JOIN units u        ON u.unit_id = o.unit_id
    JOIN route_steps rs ON rs.model_id = o.model_id AND rs.step_no = o.step_no
    JOIN work_types wt  ON wt.work_type_id = rs.work_type_id
    JOIN sections s     ON s.section_id = o.section_id
    WHERE u.serial_no = p_serial_no
    UNION ALL
    SELECT t.started_at, 'испытание', l.name,
           tt.name || CASE WHEN t.attempt_no > 1 THEN ' (повторное)' ELSE '' END
                   || ' / оборудование: ' || (SELECT string_agg(eq.name, ', ')
                                              FROM test_equipment te JOIN equipment eq USING (equipment_id)
                                              WHERE te.test_id = t.test_id),
           t.result
    FROM tests t
    JOIN units u       ON u.unit_id = t.unit_id
    JOIN labs l        ON l.lab_id = t.lab_id
    JOIN test_types tt ON tt.test_type_id = t.test_type_id
    WHERE u.serial_no = p_serial_no
    ORDER BY 1;
$$;
