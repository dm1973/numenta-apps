/*
* Numenta Platform for Intelligent Computing (NuPIC)
* Copyright (C) 2015, Numenta, Inc.  Unless you have purchased from
* Numenta, Inc. a separate commercial license for this software code, the
* following terms and conditions apply:
*
* This program is free software: you can redistribute it and/or modify
* it under the terms of the GNU General Public License version 3 as
* published by the Free Software Foundation.
*
* This program is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
* See the GNU General Public License for more details.
*
* You should have received a copy of the GNU General Public License
* along with this program.  If not, see http://www.gnu.org/licenses.
*
* http://numenta.org/licenses/
*
*/

/** Implementation of Coredatabase protocol
*/
class  CoreDatabaseImpl : CoreDatabase {
    
    let DATABASE_VERSION = 1
    var database : FMDatabase
    var dataFactory : CoreDataFactory
    var sqlHelper : SQLiteHelper
    
    var lastTimestamp : Int64 = 0
    
    /** getter for DB version
   */
    func getVersion() -> Int{
        return DATABASE_VERSION;
    }
    
    /** getter for filename
   */
    func getFileName() -> String!{
         return "grok.db"
    }
   
    /** exposed database object */
    func getReadableDatabase() -> FMDatabase!{
        return database
    }
    
    /** exposes DB object */
    func getWritableDatabase() -> FMDatabase!{
        return database
    }
    
    /** data factory getter
        - returns: datafactory used to created objects
    */
    func getDataFactory() -> CoreDataFactory!{
        return dataFactory;
    }
    
    /**
        - return: the last time in the database
    */
    func getLastTimestamp() -> Int64{
        return lastTimestamp
        
    }
    
    /** removes old records. Currently not implemented
        - returns: number of records removed
    */
    func deleteOldRecords() -> Int32{
        return -1;
    }
    
    /** removes all data from tables
    */
    func deleteAll(){
        database.beginTransaction()
        sqlHelper.delete(Annotation.TABLE_NAME, whereClause : nil, whereArgs : nil)
        sqlHelper.delete(Notification.TABLE_NAME, whereClause : nil, whereArgs : nil)
        sqlHelper.delete(MetricData.TABLE_NAME, whereClause : nil, whereArgs : nil)
        sqlHelper.delete(Metric.TABLE_NAME, whereClause : nil, whereArgs : nil)
        
        invalidateMetricCache()
        
        database.commit()
    }
    
    /** added the metric to the DB
        - parameter : metric metric to add
        - return: row id
    */
    func addMetric(metric: Metric!) -> Int64{
        var rowId : Int64 = -1
        sqlHelper.beginTransactionModeNonExclusive()
        rowId = sqlHelper.insertWithOnConflict( Metric.TABLE_NAME, values: metric.getValues(), conflictAlgorithm : SQLiteHelper.REPLACE)
        if (rowId != -1){
            updateMetricCache(metric)
        }
        sqlHelper.commit()
        return rowId
    }
    
    /** returns all the metrics in the cache
        - returns : array of metrics
    */
    func getAllMetrics() -> [Metric]!{
        let unmutableCollection = metricsCache.values.array
        return unmutableCollection
    }
    
    /** get metric from cache
        - parameter : id of metric
        - returns: metric
    */
    func getMetric(id: String!) -> Metric!{
        return metricsCache[id]
    }
    
    /** update the metric
        - parameter: metric to add
        - returns: true if successful
    */
    func updateMetric(metric: Metric!) -> Bool{
        sqlHelper.beginTransactionModeNonExclusive()
         let rows  = sqlHelper.update( Metric.TABLE_NAME, values: metric.getValues(), whereClause : "metric_id = ?", whereArgs : [metric.getId()])
        
        if (rows > 0){
            updateMetricCache(metric)
        }
        sqlHelper.commit()
        return rows>0
    }
    
    /** remove metric
        - parameter id: id of metric
        - returns: number of rows delete
    */
    func deleteMetric(id: String!) -> Int32{
        sqlHelper.beginTransactionModeNonExclusive()
        let rowsDeleted = sqlHelper.delete( Metric.TABLE_NAME , whereClause: "metric_id = ?", whereArgs:[id])
        if (rowsDeleted>0){
                removeMetricFromCache(id);
        }
        sqlHelper.commit()
        return rowsDeleted
    }
    
    /** get the metrics for the given instance id
     - parameter instanceId: id to find the metrics for
     - returns: array of metrics
    */
    func getMetricsByInstanceId(instanceId: String!) -> [Metric]!{
        var results = [Metric]()
        let values = metricsCache.values
        for metric in values {
            if (metric.getInstanceId() == instanceId){
                results.append(metric)
            }
        }
        return results;
    }
    
    /** add a collection of metric data
        - parameter batch : items to add
        - returns: true if successful
    */
    func addMetricDataBatch(batch: [MetricData]!) -> Bool{
        if (batch.isEmpty ){
            return false
        }
        
        sqlHelper.beginTransactionModeNonExclusive();
        var values = batch[0].getValues()
        let columns = [String](values.keys)
        var rowsInserted = 0
        
        let updateStatement = ("UPDATE metric SET last_timestamp = ? "  + "WHERE metric_id = ? AND last_timestamp < ?")
        let insertStatement = sqlHelper.prepareInsertStatement(MetricData.TABLE_NAME, columns : columns, status: "IGNORE")

        for metricData in batch {
            
            
            if sqlHelper.database.executeUpdate(insertStatement, withParameterDictionary: metricData.getValues()) {
                rowsInserted++
                //sqlHelper.buildInsertStatement (MetricData.TABLE_NAME, data: metricData.getValues())
                let metric = getMetric (metricData.getMetricId())
                let timestamp = metricData.getTimestamp()
                if (timestamp > metric.getLastTimestamp()){
                    if (database.executeUpdate(updateStatement, withArgumentsInArray: [String(timestamp), metric.getId(), String(timestamp)]) ){
                        metric.setLastTimestamp( timestamp)
                        updateMetricCache(metric)
                    }
                }
            }
        }
     
        return rowsInserted>0
    }

    /** fetch metric data for a date range and anomaly score
        - parameter metricId : name of metric
        - parameter columns: columns to fetch
        - parameter from: start time
        - parameter  to: end time
        - parameter anomalyCore : min anomaly score. 0 for all
        - parameter limit: number of items to return. 0 for all
        - returns: result set
    */
    func getMetricData(metricId: String!, columns: [String]!, from: NSDate!, to: NSDate!, anomalyScore: Float, limit: Int32) -> FMResultSet!{

        var selection = String()
        //var selectionArgs = [String]()
        var append = false
        if (from != nil) {
            selection += "timestamp >= " + sqlHelper.formatDate(from)
            append = true;
        }
        
        if (to != nil) {
            if (append) {
                selection+=" AND "
            }
            selection+="timestamp <= " + sqlHelper.formatDate(to)
            append = true
        }
        
        if (anomalyScore > 0) {
            if (append) {
                selection += " AND ";
            }
            selection += "anomaly_score >= " + String(anomalyScore);
            append = true;
        }
        
        if (metricId != nil) {
            if (append) {
                selection += " AND "
            }
            selection += "metric_id = '" + metricId + "'";
        }

        var limitStr:String? = nil
        if limit>0 {
            limitStr = String (limit)
        }

        let cursor  = sqlHelper.queryDistinct(MetricData.TABLE_NAME, columns: columns, whereClause: selection, limit: limitStr)
        
        return cursor
    }
    
    /** add instance data to database
        - parameter batch: instance data to add
        - returns: true for success
    */
    func addInstanceDataBatch(batch: [InstanceData]!) -> Bool{
        if (batch == nil || batch.isEmpty) {
            return false;
        }
 
        sqlHelper.beginTransactionModeNonExclusive();
        var values = batch[0].getValues()
        let columns = [String](values.keys)
        var rowsInserted = 0
        let insertStatement = sqlHelper.prepareInsertStatement(InstanceData.TABLE_NAME, columns : columns, status: "REPLACE")

        for instanceData in batch {
            if sqlHelper.database.executeUpdate(insertStatement, withParameterDictionary: instanceData.getValues()) {
                rowsInserted++
            }
        }
        sqlHelper.commit()
        return rowsInserted > 0
    }
    
    /** get instance data for time range
        - parameter instanceId: instance id of data
        - parameter columns: columns of data
        - parameter aggregation: 
        - parameter from: stat time
        - paramater to: end time
        - parameter anomalyScore : min score to fetch. 0 for all
        - parameter limit: items to fetch. 0 for all
        - returns: result set
    */
    func getInstanceData( instanceId: String!, columns: [String]!, aggregation: AggregationType!, from: NSDate!, to: NSDate!, anomalyScore: Float, limit: Int32) -> FMResultSet!{
        var selection = String()
        var append = false
        if (from != nil) {
            selection+="timestamp >= " + sqlHelper.formatDate(from)
            
            append = true;
        }
        if (to != nil) {
            if (append) {
                selection+=" AND "
            }
            selection+="timestamp <= " + sqlHelper.formatDate(to)
           
            append = true
        }
        if (aggregation != nil) {
            if (append) {
                selection+=" AND "
            }
            selection+="aggregation = " + String(aggregation.minutes())
            append = true        }
        
        if (anomalyScore > 0) {
            if (append) {
                selection+=" AND "
            }
            selection += "anomaly_score >= "
                selection += String(anomalyScore)
            append = true
        }
        
        
        if (instanceId != nil ) {
            if (append) {
                selection+=" AND "
            }
            selection += "instance_id = '" + instanceId + "'"
            append = true
        }
        
        var limitStr:String? = nil
        if  limit>0 {
            limitStr = String (limit)
        }
    
        let cursor  = sqlHelper.queryDistinct(InstanceData.TABLE_NAME, columns: columns, whereClause: selection,  limit: limitStr)
    
        return cursor
    }
    
    /** Get all instances from Metric. Note this routine will load the cache which might be slow
        - returns: set of incance ids
    */
    func getAllInstances() -> Set<String>!{
        if (instanceToName.isEmpty) {
            loadMetricCache()
        }
        
        var instances = Set<String>()
        let results =  instanceToName.keys
        
        for key in results{
            instances.insert (key)
        }
       return instances
    }
    
    /** update the Instance data
        - parameter : instance to update
        - returns:  true for success
    */
    func updateInstanceData(_instanceData: InstanceData!) -> Bool{
        
        sqlHelper.beginTransactionModeNonExclusive()
        
        let rows = sqlHelper.update(InstanceData.TABLE_NAME, values: _instanceData.getValues(), whereClause: "aggregation = ? AND instance_id = ? AND timestamp = ?",
                whereArgs: [String(_instanceData.getAggregation()), _instanceData.getInstanceId(), String(_instanceData.getTimestamp())])

        sqlHelper.commit()
        return rows > 0
    }
    
    
    /** Remove instance from DB
        - parameter instance : id of instance to remove
    */
    func deleteInstance(instance: String!){
        deleteInstanceData(instance)
        instanceToName.removeValueForKey(instance)
        // Remove annotations associated to this instance
        deleteAnnotationByInstanceId(instance)
        
        var metrics = getMetricsByInstanceId(instance)
        // Remove metrics associated to this instance
         metrics = getMetricsByInstanceId(instance);
        for  metric in metrics {
            deleteMetric(metric.getId())
        }

    }
    
    /** remove data for instance id
        -parameter instanceId : id of instance to remove
    */
    func deleteInstanceData(instanceId: String!){
        
        sqlHelper.beginTransactionModeNonExclusive()
        sqlHelper.delete( InstanceData.TABLE_NAME , whereClause: "instance_id = ?", whereArgs:[instanceId])
                sqlHelper.commit()
        sqlHelper.commit()
        
    }
    
    /** Returns server name for instance id. Note will load  if needed
        - parameter instanceId:  id of instance
        - returns:   String: server name
    */
    func getServerName(instanceId: String!) -> String!{
       
        getAllInstances()
        var name = instanceToName[instanceId]
        
        // FIXME need to trim name?
        if  name != nil
        {
            if name!.isEmpty == false {
                return name
            }
        }
        return instanceId
    }
    
    /** Save notification in database
        - parameter notificationId : id of notification
        - parameter metridId:    metric id
        - parameter timestampe : time stamp
        - parameter decription:
        - returns: id of added notification
    */
    func addNotification(notificationId: String!, metricId: String!, timestamp: Int64, description: String!) -> Int64{
        var rowId :Int64 = -1
        let notification = Notification(notificationId: notificationId, metricId: metricId, timestamp: timestamp, read: false, description: description)
        sqlHelper.beginTransactionModeNonExclusive()
        rowId = sqlHelper.insertWithOnConflict( Notification.TABLE_NAME, values: notification.getValues(), conflictAlgorithm : SQLiteHelper.REPLACE)
                sqlHelper.commit()
        return rowId

    }
    
    /** Get an array of all notifications
        - returns: array of notifications
    */
    func getAllNotifications() -> [Notification]!{
        var  results = [Notification]();
        
        let cursor = sqlHelper.queryAll(Notification.TABLE_NAME)
        
        while cursor.next() {
                results.append(dataFactory.createNotification(cursor))
            }
        
        cursor.close()
        if results.isEmpty{
            return nil
        }
        return results

    }
    
    /** retrieve notifcation by local id
        - parameter localId : id of notication
        - returns: notification. nil for no notification
    */
    func getNotificationByLocalId(localId: Int32) -> Notification!{
        
        
        var result: Notification! = nil;
        let cursor = sqlHelper.query( Metric.TABLE_NAME , columns: nil, whereClause:"_id = ?", whereArgs:[String(localId)], sortBy: nil)

            if (cursor.next()) {
                result =  Notification(cursor: cursor)
            }
            
        cursor.close()
        return result
    }
    
    /** get count of unread notifications
        - returns: number of unread notifications
    */
    func getUnreadNotificationCount() -> Int32{
        return sqlHelper.queryNumEntries(Notification.TABLE_NAME, whereClause: "read = 0")
    }
    
    
    /** get number of notifications
        - returns: number of notifications
    */
    func getNotificationCount() -> Int32{
        return sqlHelper.queryNumEntries(Notification.TABLE_NAME, whereClause: nil)
    }
    
    /** mark the specified notification as read
        - parameter notificaiotnId : id of notification
        - results : true if marked read
    */
    func markNotificationRead(notificationId: Int32) -> Bool{
        sqlHelper.beginTransactionModeNonExclusive()
        
        var values = Dictionary<String, Any>()
        values["read"] = 1

        let rows  = sqlHelper.update( Notification.TABLE_NAME, values: values, whereClause : "_id = ?", whereArgs : [String(notificationId)])
        sqlHelper.commit()
        return rows>0
    }
    
    
    /** delete the specified notification
    - parameter localId : id of notification
    - results : rows deleted
    */
    func deleteNotification(localId: Int32) -> Int32{
        
        sqlHelper.beginTransactionModeNonExclusive()
        let deleted = sqlHelper.delete( Notification.TABLE_NAME , whereClause: "_id = ?", whereArgs:[String(localId)])
        sqlHelper.commit()
       
        return deleted;
    }
    
    
    /** delete all notifications
    - results : rows deleted
    */
    func deleteAllNotifications() -> Int32{
        sqlHelper.beginTransactionModeNonExclusive()
        let deleted = sqlHelper.delete( Notification.TABLE_NAME , whereClause: "1", whereArgs:nil)
        sqlHelper.commit()
      
        return deleted;
    }
    
    
    /** Add annotation to DB
        - parameter annotation: annotation to add
        - returns: id of added annotation
    */
    func addAnnotation(annotation: Annotation!) -> Int64{
        if instanceToName[annotation.getId()]==nil{
            //"Failed to add annotation to database. Missing or unknown instance id"
            return -1;
        }
        var rowId :Int64 = -1
          sqlHelper.beginTransactionModeNonExclusive()
        rowId = sqlHelper.insertWithOnConflict( Annotation.TABLE_NAME,  values: annotation.getValues(), conflictAlgorithm : SQLiteHelper.REPLACE)
        sqlHelper.commit()
        return rowId


    }
    
    /** get array of all annotations
        - returns: array of annotations
    */
    func getAllAnnotations() -> [Annotation]!{

        var  results = [Annotation]();
        
        let cursor = sqlHelper.queryAll(Annotation.TABLE_NAME)
        
        while cursor.next() {
            results.append(dataFactory.createAnnotation(cursor))
        }
        
        cursor.close()
        if results.isEmpty{
            return nil
        }
        return results
    }
    
    /** retrun annotation for given id
        - parameter id: id of annotation
        - returns: annotation
    */
    func getAnnotation(id: String!) -> Annotation!{
        
        var result :Annotation! = nil
        
        let cursor = sqlHelper.query( Annotation.TABLE_NAME , columns: nil, whereClause:"annotation_id = ?", whereArgs:[String(id)], sortBy: nil)
   
        if (cursor.next()) {
             result =  Annotation(cursor: cursor)
        }
        cursor.close()
        
        return result
    }
    
    
    /** fetch the annotations
        - parameter server: 
        - parameter from: start date
        - parameter to: end date
        - returns: arrays of annotations
    */
    func getAnnotations(server: String!, from: NSDate!, to: NSDate!) -> [Annotation]!{
        var selection = String()
        var selectionArgs = [String]()
        var append = false
        if (from != nil) {
            selection+="timestamp >= ?";
            selectionArgs.append(sqlHelper.formatDate(from))
            append = true;
        }
        if (to != nil) {
            if (append) {
                selection+=" AND "
            }
            selection+="timestamp <= ?"
            selectionArgs.append(sqlHelper.formatDate(to))
            append = true
        }
        if (server != nil) {
            if (append) {
                selection+=" AND ";
            }
            selection+="instance_id = ?"
            selectionArgs.append(server)
        }
            var results = [Annotation]()
        let cursor  = sqlHelper.query(Annotation.TABLE_NAME, columns: nil,  whereClause: selection, whereArgs: selectionArgs, sortBy: "timestamp ASC, created ASC")
        
        while (cursor.next()) {
            results.append(dataFactory.createAnnotation(cursor))
        }
        cursor.close()
        return results;
    }
    
    
    /** remove annotation by annotation id
    - parameter id: annotation Id
    - returns: rows deleted
    */
    func deleteAnnotation(id: String!) -> Int32{
        sqlHelper.beginTransactionModeNonExclusive()
        let rowsDeleted = sqlHelper.delete( Annotation.TABLE_NAME , whereClause: "annotation_id = ?", whereArgs:[id])
        
        sqlHelper.commit()
        return rowsDeleted

    }
    
    /** remove annotation by instance id
        - parameter instanceId: instance Id
        - returns: rows deleted
    */
    func deleteAnnotationByInstanceId(instanceId: String!) -> Int32{
        sqlHelper.beginTransactionModeNonExclusive()
        let rowsDeleted = sqlHelper.delete( Annotation.TABLE_NAME , whereClause: "instance_id = ?", whereArgs:[instanceId])
      
        sqlHelper.commit()
        return rowsDeleted
    }


    // Internal funcs
    
    private var metricsCache = [String : Metric]()
    private var instanceToName = [String : String]()
    
    /** removes all items from the cache
    */
    private func invalidateMetricCache(){
        instanceToName.removeAll()
        metricsCache.removeAll()
    }
    
    /** updates the cache for the metric
        - parameter metric: metric to add to cache
    */
    private func updateMetricCache( metric : Metric ){
        metricsCache[metric.getId()] = metric;
        instanceToName[metric.getInstanceId()] = metric.getServerName()
    }
    
    /** remove metric from a the cache
      - parameter id: id of metric to remove
      - returns: metric that was removed
    */
    private func removeMetricFromCache (id: String)->Metric?{
        if let metric =  metricsCache.removeValueForKey(id){
            instanceToName.removeValueForKey( metric.getInstanceId())
             deleteAnnotationByInstanceId(metric.getInstanceId())
            return metric
        }
    	
        return nil
    }
    
    
    /** load the metric cache
    */
    private func loadMetricCache(){
        invalidateMetricCache()
        let cursor = sqlHelper.queryDistinct(Metric.TABLE_NAME, columns: nil, whereClause: nil, limit: nil)
        
        if (cursor == nil){
            return
        }
        while cursor.next(){
            let metric = dataFactory.createMetric(cursor)
            instanceToName[metric.getInstanceId()] =  metric.getServerName()
            metricsCache[metric.getId()] = metric
            
        }
    }
    
    /**
    - parameter dataFactory : factory to create objects
    */
    init(dataFactory : CoreDataFactory ){
        sqlHelper = SQLiteHelper(name: "grok.db")
        database = sqlHelper.database;
        self.dataFactory  = dataFactory
    }

}