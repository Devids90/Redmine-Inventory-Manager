class InventoryController < ApplicationController
  unloadable

  def index
    sql = ActiveRecord::Base.connection()
    @warehouses = InventoryWarehouse.find(:all, :order => 'name').map {|w| [w.name, w.id]}
    @warehouses += [l('all_warehouses')]
    
    add = ""
    unless params[:warehouse]
      params[:warehouse] = l('all_warehouses')
    end
    
    if params[:warehouse] != l('all_warehouses')
      add = " AND (`inventory_movements`.`warehouse_from_id` = #{params[:warehouse]} OR " +
            "`inventory_movements`.`warehouse_to_id` = #{params[:warehouse]})"
      params[:warehouse] = params[:warehouse].to_i
    end
    
    @stock = sql.execute("SELECT in_movements.part_number as part_number,
          in_movements.serial_number as serial_number,
          in_movements.value,
          IFNULL(in_movements.quantity,0) as input,
          IFNULL(out_movements.quantity,0) as output,
          (IFNULL(in_movements.quantity,0)-IFNULL(out_movements.quantity,0)) as stock,
          GREATEST(IFNULL(in_movements.last_date,0), IFNULL(out_movements.last_date,0)) as last_movement
            FROM
        (SELECT `inventory_parts`.`part_number` AS `part_number`,`inventory_movements`.`serial_number` AS `serial_number`,
            `inventory_parts`.`value` AS `value`,sum(`inventory_movements`.`quantity`) AS `quantity`,
            max(`inventory_movements`.`date`) AS `last_date`
              FROM (`inventory_parts`
                LEFT JOIN `inventory_movements` on((`inventory_movements`.`inventory_part_id` = `inventory_parts`.`id`)))
                  WHERE (isnull(`inventory_movements`.`inventory_providor_id`) AND isnull(`inventory_movements`.`user_from_id`)"+add+"
                    AND ((`inventory_movements`.`project_id` is not null) or (`inventory_movements`.`user_to_id` is not null)))
                      GROUP BY `inventory_parts`.`id`,`inventory_movements`.`serial_number`
                      ORDER BY `inventory_parts`.`part_number`) as out_movements
              RIGHT JOIN
        (SELECT `inventory_parts`.`part_number` AS `part_number`,`inventory_movements`.`serial_number` AS `serial_number`,
            `inventory_parts`.`value` AS `value`,sum(`inventory_movements`.`quantity`) AS `quantity`,
            max(`inventory_movements`.`date`) AS `last_date`
              FROM (`inventory_parts`
                LEFT JOIN `inventory_movements` on((`inventory_movements`.`inventory_part_id` = `inventory_parts`.`id`)))
                  WHERE (isnull(`inventory_movements`.`project_id`) and isnull(`inventory_movements`.`user_to_id`))"+add+"
                    GROUP BY `inventory_parts`.`id`,`inventory_movements`.`serial_number`
                    ORDER BY `inventory_parts`.`part_number`) as in_movements
              ON
                (out_movements.part_number = in_movements.part_number
                AND out_movements.serial_number = in_movements.serial_number);")
  end

  def ajax_get_part_value
    out = ''
    if params[:part_id]
      if part = InventoryPart.find(params[:part_id])
        out =  part.value.to_s
      end
    end
    render :text => out
  end

  def check_available_stock(movement)
    add = " AND (`inventory_movements`.`warehouse_from_id` = #{movement.warehouse_from_id} OR " +
            "`inventory_movements`.`warehouse_to_id` = #{movement.warehouse_from_id}) AND
            `inventory_movements`.`inventory_part_id` = #{movement.inventory_part_id}"
    
    unless movement.serial_number.blank?
      add << " AND `inventory_movements`.`serial_number` = '#{movement.serial_number}'"
    end
    sql = ActiveRecord::Base.connection()
    @stock = sql.execute("SELECT in_movements.part_number as part_number,
          in_movements.serial_number as serial_number,
          in_movements.value,
          IFNULL(in_movements.quantity,0) as input,
          IFNULL(out_movements.quantity,0) as output,
          (IFNULL(in_movements.quantity,0)-IFNULL(out_movements.quantity,0)) as stock,
          GREATEST(IFNULL(in_movements.last_date,0), IFNULL(out_movements.last_date,0)) as last_movement
            FROM
        (SELECT `inventory_parts`.`part_number` AS `part_number`,`inventory_movements`.`serial_number` AS `serial_number`,
            `inventory_parts`.`value` AS `value`,sum(`inventory_movements`.`quantity`) AS `quantity`,
            max(`inventory_movements`.`date`) AS `last_date`
              FROM (`inventory_parts`
                LEFT JOIN `inventory_movements` on((`inventory_movements`.`inventory_part_id` = `inventory_parts`.`id`)))
                  WHERE (isnull(`inventory_movements`.`inventory_providor_id`) AND isnull(`inventory_movements`.`user_from_id`)"+add+"
                    AND ((`inventory_movements`.`project_id` is not null) or (`inventory_movements`.`user_to_id` is not null)))
                      GROUP BY `inventory_parts`.`id`,`inventory_movements`.`serial_number`
                      ORDER BY `inventory_parts`.`part_number`) as out_movements
              RIGHT JOIN
        (SELECT `inventory_parts`.`part_number` AS `part_number`,`inventory_movements`.`serial_number` AS `serial_number`,
            `inventory_parts`.`value` AS `value`,sum(`inventory_movements`.`quantity`) AS `quantity`,
            max(`inventory_movements`.`date`) AS `last_date`
              FROM (`inventory_parts`
                LEFT JOIN `inventory_movements` on((`inventory_movements`.`inventory_part_id` = `inventory_parts`.`id`)))
                  WHERE (isnull(`inventory_movements`.`project_id`) and isnull(`inventory_movements`.`user_to_id`))"+add+"
                    GROUP BY `inventory_parts`.`id`,`inventory_movements`.`serial_number`
                    ORDER BY `inventory_parts`.`part_number`) as in_movements
              ON
                (out_movements.part_number = in_movements.part_number
                AND out_movements.serial_number = in_movements.serial_number);").fetch_row
    return @stock[5].to_f rescue 0
  end

  def movements
    @parts = InventoryPart.find(:all, :order => 'part_number').map {|p| [p.part_number,p.id]}
    @providors = InventoryProvidor.find(:all, :order => 'name').map {|p| [p.name,p.id]}
    @inv_projects = Project.find(:all, :order => 'name').map {|p| [p.name,p.id]}
    @users = User.find(:all, :conditions => 'status=1' , :order => 'lastname ASC, firstname ASC').map {|u| [u.lastname+" "+u.firstname, u.id]}
    @warehouses = InventoryWarehouse.find(:all, :order => 'name').map {|w| [w.name, w.id]}
    @from_options = {l('User') => 'user_from_id', l('Warehouse') => 'warehouse_from_id', l('Providor') => 'inventory_providor_id'}
    @to_options = {l('User') => 'user_to_id', l('Project') => 'project_id'}
    
    unless params[:from_options]
      params[:from_options] = 'user_from_id'
    end
    
    unless params[:to_options]
      params[:to_options] = 'user_to_id'
    end
    
    if params[:delete]
      ok = InventoryMovement.delete(params[:delete]) rescue false
      unless ok
        flash[:error] = l('cant_delete_register')
      end
    end
    
    if params[:edit_in]
      @inventory_in_movement = InventoryMovement.find(params[:edit_in])
      if @inventory_in_movement.user_from_id
        params[:from_options] = 'user_from_id'
      elsif @inventory_in_movement.inventory_providor
        params[:from_options] = 'inventory_providor_id'
      elsif @inventory_in_movement.warehouse_from_id
        params[:from_options] = 'warehouse_from_id'
      end
    else
      @inventory_in_movement = InventoryMovement.new
    end
    
    if params[:inventory_in_movement]
      unless params[:edit_in]
        @inventory_in_movement = InventoryMovement.new(params[:inventory_in_movement]) 
        @inventory_in_movement.user_id = find_current_user.id
        @inventory_in_movement.date = DateTime.now
        if @inventory_in_movement.save
          @inventory_in_movement = InventoryMovement.new(params[:inventory_in_movement])
          @inventory_in_movement.inventory_part = nil
          @inventory_in_movement.serial_number = nil
          @inventory_in_movement.quantity = nil
          @inventory_in_movement.value = nil
          params[:create_in]  = true
        end
      else
        if @inventory_in_movement.update_attributes(params[:inventory_in_movement])
          params[:edit_in] = false
        end
      end
    end
    
    if params[:edit_out]
      @inventory_out_movement = InventoryMovement.find(params[:edit_out])
      if @inventory_out_movement.user_from_id
        params[:to_options] = 'user_to_id'
      elsif @inventory_out_movement.inventory_providor
        params[:to_options] = 'project_id'
      end
    else
      @inventory_out_movement = InventoryMovement.new
    end
    
    if params[:inventory_out_movement]
      unless params[:edit_out]
        @inventory_out_movement = InventoryMovement.new(params[:inventory_out_movement]) 
        available_stock = check_available_stock(@inventory_out_movement)
        if @inventory_out_movement.quantity <= available_stock
          @inventory_out_movement.user_id = find_current_user.id
          @inventory_out_movement.date = DateTime.now
          if @inventory_out_movement.save
            @inventory_out_movement = InventoryMovement.new(params[:inventory_out_movement])
            @inventory_out_movement.inventory_part = nil
            @inventory_out_movement.serial_number = nil
            @inventory_out_movement.quantity = nil
            @inventory_out_movement.value = nil
            params[:create_out]  = true
          end
        else
          flash[:error] = l('out_of_stock')
        end
      else
        ok = true
        if @inventory_out_movement.quantity < params[:inventory_out_movement][:quantity].to_f
          available_stock = check_available_stock(@inventory_out_movement)
          unless (params[:inventory_out_movement][:quantity].to_f - @inventory_out_movement.quantity) <= available_stock
            ok = false
          end
        end
        if ok
          if @inventory_out_movement.update_attributes(params[:inventory_out_movement])
            params[:edit_out] = false
          end
        else
          flash[:error] = l('out_of_stock')
        end
      end
    end

    @movements_in = InventoryMovement.find(:all, :conditions => "project_id is null and user_to_id is null", :order => "date DESC", :limit => 100)
    @movements_out = InventoryMovement.find(:all, :conditions => "inventory_providor_id is null and user_from_id is null and (project_id is not null or user_to_id is not null)", :order => "date DESC", :limit => 100)
  end

  def categories
    if params[:delete]
      ok = InventoryCategory.delete(params[:delete]) rescue false
      unless ok
        flash[:error] = l('cant_delete_register')
      end
    end
    
    if params[:edit]
      @inventory_category = InventoryCategory.find(params[:edit])
    else
      @inventory_category = InventoryCategory.new
    end
    
    if params[:inventory_category]
      @inventory_category.update_attributes(params[:inventory_category]) 
      if @inventory_category.save
        @inventory_category = InventoryCategory.new
        params[:edit] = false
        params[:create]  = false
      end
    end
    
    @categories = InventoryCategory.find(:all)
  end

  def parts
    @categories = InventoryCategory.find(:all, :order => 'name').map {|c| [c.name,c.id]}
    if params[:delete]
      ok = InventoryPart.delete(params[:delete]) rescue false
      unless ok
        flash[:error] = l('cant_delete_register')
      end
    end
    
    if params[:edit]
      @inventory_part = InventoryPart.find(params[:edit])
    else
      @inventory_part = InventoryPart.new
    end
    
    if params[:inventory_part]
      @inventory_part.update_attributes(params[:inventory_part]) 
      if @inventory_part.save
        @inventory_part = InventoryPart.new
        params[:edit] = false
        params[:create]  = false
      end
    end

    @parts = InventoryPart.find(:all)
  end
  
  def providors
    if params[:delete]
      ok = InventoryProvidor.delete(params[:delete]) rescue false
      unless ok
        flash[:error] = l('cant_delete_register')
      end
    end
    
    if params[:edit]
      @inventory_providor = InventoryProvidor.find(params[:edit])
    else
      @inventory_providor = InventoryProvidor.new
    end
    
    if params[:inventory_providor]
      @inventory_providor.update_attributes(params[:inventory_providor]) 
      if @inventory_providor.save
        @inventory_providor = InventoryProvidor.new
        params[:edit] = false
        params[:create]  = false
      end
    end
    
    @providors = InventoryProvidor.find(:all)
  end
  
  def warehouses
    if params[:delete]
      ok = InventoryWarehouse.delete(params[:delete]) rescue false
      unless ok
        flash[:error] = l('cant_delete_register')
      end
    end
    
    if params[:edit]
      @inventory_warehouse = InventoryWarehouse.find(params[:edit])
    else
      @inventory_warehouse = InventoryWarehouse.new
    end
    
    if params[:inventory_warehouse]
      @inventory_warehouse.update_attributes(params[:inventory_warehouse]) 
      if @inventory_warehouse.save
        @inventory_warehouse = InventoryWarehouse.new
        params[:edit] = false
        params[:create]  = false
      end
    end
    
    @warehouses = InventoryWarehouse.find(:all)
  end
end