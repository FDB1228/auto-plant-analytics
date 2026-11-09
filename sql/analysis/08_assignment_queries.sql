-- Виды запросов из задания учебной практики - теперь функции операционной БД (sql/oltp/02_functions_triggers.sql)

-- 1. Число и перечень изделий по категориям и в целом, собранных цехом / участком / заводом за период
select * from plant.report_units_assembled('2026-09-01', '2026-09-30');                             -- завод
select * from plant.report_units_assembled('2026-09-01', '2026-09-30', p_workshop_id => 2::smallint); -- цех
select * from plant.report_units_assembled('2026-09-01', '2026-09-30', p_section_id => 4::smallint);  -- участок

-- 2. Участки цеха / завода и их начальники (вакансия = NULL)
select * from plant.report_sections_and_heads(3::smallint, '2026-09-30');
select * from plant.report_sections_and_heads(p_on_date => '2026-09-30');

-- 3. Состав бригад, участвовавших в сборке указанного изделия (на дату работ)
select * from plant.report_brigades_for_unit(
    (select serial_no from plant.units where model_id = 6 and status = 'shipped' order by unit_id desc limit 1));

-- 4. Состав бригад участка / цеха на дату
select * from plant.report_brigade_composition(p_section_id => 4::smallint, p_on_date => '2026-09-30');
select * from plant.report_brigade_composition(p_workshop_id => 3::smallint, p_on_date => '2026-09-30');

-- 5. Перечень работ изделия: нормативный маршрут модели и фактическая история экземпляра
select * from plant.report_model_route('G1000');
select * from plant.report_unit_history(
    (select u.serial_no from plant.units u join plant.defects d using (unit_id)
     where d.detection_point = 'test' order by u.unit_id limit 1));

-- 6. Изменение и «удаление» (увольнение) рабочего - в транзакции с откатом, чтобы не менять демо-данные
begin;
select plant.update_worker(1, p_skill_grade => 5::smallint);
select plant.terminate_worker(1, '2026-09-30');
select employee_id, full_name, termination_date from plant.employees where employee_id = 1;
select plant.delete_worker(1);   -- ошибка: у рабочего есть производственная история -> только увольнение
rollback;
