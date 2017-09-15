global class Trello implements Schedulable {
    /* What this is - it accesses your trello account and keeps mirrored Tasks in SF
     * that map to the appropriate Accounts by matching the account name to the name of the containing
     * -board in trello.  It populates the description and 3 newest comments in the description section of task
     * (new tasks are added automatically)
     * (existing tasks are updated)
     * (tasks are deleted when their matching trello cards are deleted)
     *
     * Requirements to implement Trello connection:
     * 1. make a task record type called 'Trello'
     * 2. make a field on Task called Trello_Card_ID (type text 255 chars)
     * 3. schedule the execution of this code by going into setup->apex_classes->schedule
     * 4. replace apiKey and apiToken with your trello api key / token values
     */
    private static String apiKey = '';
    private static String apiToken = '';
    private static String baseApi = '';
    private static String username = '';
    public class myException extends Exception {}
    public void execute(SchedulableContext sc) {
        refreshTrello();
    }
    public static void getCreds(){
        apiKey = String.valueOf([SELECT TrelloTasks__API_Key__c FROM TrelloTasks__TrelloTaskConfig__c WHERE TrelloTasks__Zero_here_for_the_one_you_want_to_use__c = 0 LIMIT 1].TrelloTasks__API_Key__c);
        apiToken = String.valueOf([SELECT TrelloTasks__API_Token__c FROM TrelloTasks__TrelloTaskConfig__c WHERE TrelloTasks__Zero_here_for_the_one_you_want_to_use__c = 0 LIMIT 1].TrelloTasks__API_Token__c);
        baseApi = String.valueOf([SELECT TrelloTasks__API_Endpoint__c FROM TrelloTasks__TrelloTaskConfig__c WHERE TrelloTasks__Zero_here_for_the_one_you_want_to_use__c = 0 LIMIT 1].TrelloTasks__API_Endpoint__c);
        username = String.valueOf([SELECT TrelloTasks__API_Username__c FROM TrelloTasks__TrelloTaskConfig__c WHERE TrelloTasks__Zero_here_for_the_one_you_want_to_use__c = 0 LIMIT 1].TrelloTasks__API_Username__c);
    }
    public static HttpResponse execGetCall(String endpoint){
        Http http = new Http();
        HttpRequest request = new HttpRequest();
        if (endpoint.contains('?')) {
            request.setEndpoint(endpoint+'&key='+apiKey+'&token='+apiToken);
        } else {
            request.setEndpoint(endpoint+'?key='+apiKey+'&token='+apiToken);
        }
        request.setMethod('GET');
        HttpResponse response = http.send(request);
        // If the request is successful, parse the JSON response.
        if (response.getStatusCode() == 200) {
            // Deserialize the JSON string into collections of primitive data types.
            //Map<String, Object> results = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
            // Cast the values in the 'animals' key as a list
            //List<Object> animals = (List<Object>) results.get('animals');
            System.debug('Received the following results:'+response.getBody());
            //for (Object animal: animals) {
                //System.debug(animal);
            //}
        }
        return response;
    }
    public static void getToken(){
        HttpResponse response = execGetCall(baseApi+'/tokens/'+apiToken+'?key='+apiKey);
    }
    public static Map<String, String> getBoards(){
        // map<boardID, boardName>
        Map<String, String> retBoards = new Map<String, String>();

        HttpResponse response = execGetCall(baseApi+'/members/'+username+'/boards');
        List<Object> boards = (List<Object>) JSON.deserializeUntyped(response.getBody());
        for (Object board : boards) {
            Map<String, Object> boardStrings = (Map<String,Object>) board;
            System.debug(boardStrings.get('name')+' '+boardStrings.get('id'));
            retBoards.put(String.valueOf(boardStrings.get('id')),
                          String.valueOf(boardStrings.get('name')));
        }

        return retBoards;
    }
    public static Task getTask(String taskId, Task task, Map<String, Object> taskFromTrello, Map<String, Object> taskComments){
        if (task == null){
            task = new Task();
        }

        String taskName;
        String taskDesc;
        Date taskDueDate;
        String taskCommentsString = '';
        String taskStatus;

        List<String> checklistIds = new List<String>();

        //set all fields on Task based on looked up data from trello card
        taskName = String.valueOf(taskFromTrello.get('name'));
        taskDesc = String.valueOf(taskFromTrello.get('desc'));
        if (taskFromTrello.get('due') != null) {
        	taskDueDate = Date.valueOf(String.valueOf(taskFromTrello.get('due')));
        } else {
            taskDueDate = null;
        }

        //get 3 most recent comments
        List<Object> trelloComments = (List<Object>) taskComments.get(taskId);
        //***limit to three comments
        if (trelloComments != null) {
            Integer commentCount = 0;
        	for (Object comment : trelloComments) {
                if (commentCount < 3) {
                	Map<String, Object> commentStrings = (Map<String, Object>) comment;
                    Map<String, Object> commentData = (Map<String, Object>) commentStrings.get('data');
                    String commentDate = String.valueOf(commentStrings.get('date'));
                    String commentText = String.valueOf(commentData.get('text'));
                    Map<String, Object> commentOwner = (Map<String, Object>) commentStrings.get('memberCreator');
                    String commentOwnerName = String.valueOf(commentOwner.get('fullName'));
                    taskCommentsString = taskCommentsString + '\n\n>>>>>>>>>>>>Comment Date: '+commentDate+' by: '+commentOwnerName+'\n'+commentText;
                    commentCount = commentCount + 1;
                } else {
                    break;
                }
            }
        }

        //***determine if all checklists on card are checked
        Integer completeChecklistItems = 0;
        Integer incompleteChecklistItems = 0;
        Map<String, Object> badges = (Map<String, Object>) taskFromTrello.get('badges');
        completeChecklistItems = Integer.valueOf(badges.get('checkItemsChecked'));
        incompleteChecklistItems = Integer.valueOf(badges.get('checkItems')) - completeChecklistItems;

        if (completeChecklistItems > 0 && incompleteChecklistItems == 0) {
            taskStatus = 'Completed';
        } else if (completeChecklistItems == 0) {
            taskStatus = 'Not Started';
        } else {
            taskStatus = 'In Progress';
        }

        if (!Schema.sObjectType.Task.fields.Subject.isUpdateable() || !Schema.sObjectType.Task.fields.Subject.isCreateable()
            || !Schema.sObjectType.Task.fields.Description.isUpdateable() || !Schema.sObjectType.Task.fields.Description.isCreateable()
            || !Schema.sObjectType.Task.fields.ActivityDate.isUpdateable() || !Schema.sObjectType.Task.fields.ActivityDate.isCreateable()
            || !Schema.sObjectType.Task.fields.Trello_Card_ID__c.isUpdateable() || !Schema.sObjectType.Task.fields.Trello_Card_ID__c.isCreateable()
            || !Schema.sObjectType.Task.fields.Status.isUpdateable() || !Schema.sObjectType.Task.fields.Status.isCreateable()){
                throw new myException('cant access Task');
        } else {
            task.Subject = taskName;
            task.Description = taskDesc+'\n\n--------top 3 newest comments---------'+taskCommentsString;
            task.ActivityDate = taskDueDate;
            task.Trello_Card_ID__c = taskId;
            task.Status = taskStatus;

            return task;
        }

    }
    @future (callout=true)
    public static void refreshTrello(){
        getCreds();

        //create a list to hold all new/updated/to-delete tasks
        List<Task> newTasks = new List<Task>();
        List<Task> updatedTasks = new List<Task>();
        List<Task> toDeleteTasks = new List<Task>();

        String trelloTaskRecordTypeId = [SELECT Id FROM RecordType WHERE Name = 'Trello' LIMIT 1].Id;

    	//create map of existing trello tasks to accountids (map<AccountID, map<TrelloCardID, Task>>)
    	Map<Id, Map<String, Task>> existingTasks = new Map<Id, Map<String, Task>>();
        Map<String, Task> newTaskList;
        for (Task task : [SELECT Id, Subject, Description, ActivityDate, Status, WhatId, Trello_Card_ID__c FROM Task WHERE RecordType.Name = 'Trello']){
        	// only process tasks related to Accounts
			if(task.WhatId.getSObjectType() == Account.getSObjectType()){
                if(existingTasks.containsKey(task.WhatID)){
                    newTaskList = existingTasks.get(task.WhatID);
                } else {
                    newTaskList = new Map<String, Task>();
                }
                newTaskList.put(task.Trello_Card_ID__c, task);
                existingTasks.put(task.WhatId, newTaskList);
            }
        }

        //create a map of accounts (map<AcctName, AccountId>)
        Map<String, Id> accounts = new Map<String, Id>();
        for (Account acct : [SELECT Id, Name FROM Account]){
            accounts.put(acct.Name, acct.Id);
        }

        //match up boards to accounts
        if (test.isRunningTest()) { callout_mocks_for_Trello.setMock('getBoards'); }
        Map<String, String> boards = getBoards();
        for (String boardId : boards.keySet()) {
            //see if board matches an account
            String boardName = boards.get(boardId);
            if (!accounts.containsKey(boardName)) {
                // if there's no matching account, remove board from list 'boards'
                boards.remove(boardId);
            }
        }

        //collect trello-retrieved tasks Map<boardId, List<Object>>
        if (test.isRunningTest()) { callout_mocks_for_Trello.setMock('getTasks'); }
        Map<String, List<Object>> trelloTasks = new Map<String, List<Object>>();
        String endpoint = baseApi + '/batch/?urls=';
        for (String boardId : boards.keySet()) {
            endpoint = endpoint + '/board/' + boardId + '/cards' + ',';
        }
        endpoint = endpoint.substring(0, endpoint.length()-1);
		HttpResponse response = execGetCall(endpoint);
        //process returned tasks and add them to trelloTasks
        List<Object> batchResponses = (List<Object>) JSON.deserializeUntyped(response.getBody());
        for (Object batchResponse : batchResponses) {
            Map<String, Object> boardTasksResponse = (Map<String, Object>) batchResponse;
            if (boardTasksResponse.containsKey('200')) {
                List<Object> boardTaskList = (List<Object>) boardTasksResponse.get('200');
                for (Object retrievedTask : boardTaskList) {
                    Map<String, Object> trelloTask = (Map<String, Object>) retrievedTask;
                    String trelloTaskBoardId = String.valueOf(trelloTask.get('idBoard'));
                    if (trelloTasks.containsKey(trelloTaskBoardId)) {
                        List<Object> updatedBoardTasks = trelloTasks.get(trelloTaskBoardId);
                        updatedBoardTasks.add(retrievedTask);
                        trelloTasks.put(trelloTaskBoardId, updatedBoardTasks);
                    } else {
                        List<Object> newBoardTasks = new List<Object>();
                        newBoardTasks.add(retrievedTask);
                        trelloTasks.put(trelloTaskBoardId, newBoardTasks);
                    }
                }
            }
        }

        //***get all comments for boards
        //map<taskId, Object>
        if (test.isRunningTest()) { callout_mocks_for_Trello.setMock('getComments'); }
        Map<String, List<Object>> taskComments = new Map<String, List<Object>>();
        endpoint = baseApi + '/batch/?urls=';
        for (String boardId : boards.keySet()) {
            endpoint = endpoint + '/board/' + boardId + '/actions' + ',';
        }
        endpoint = endpoint.substring(0, endpoint.length()-1);
		response = execGetCall(endpoint);
        //process returned comments and add them to taskComments
        batchResponses = (List<Object>) JSON.deserializeUntyped(response.getBody());
        for (Object batchResponse : batchResponses) {
            Map<String, Object> boardCommentsResponse = (Map<String, Object>) batchResponse;
            if (boardCommentsResponse.containsKey('200')) {
                List<Object> boardCommentList = (List<Object>) boardCommentsResponse.get('200');
                for (Object retrievedComment : boardCommentList) {
                    Map<String, Object> taskComment = (Map<String, Object>) retrievedComment;
                    if (String.valueOf(taskComment.get('type')) == 'commentCard') {
                        Map<String, Object> taskCommentData = (Map<String, Object>) taskComment.get('data');
                        Map<String, Object> taskCommentCard = (Map<String, Object>) taskCommentData.get('card');
                        String trelloCommentTaskId = String.valueOf(taskCommentCard.get('id'));
                        if (taskComments.containsKey(trelloCommentTaskId)) {
                            List<Object> updatedTaskComments = taskComments.get(trelloCommentTaskId);
                            updatedTaskComments.add(retrievedComment);
                            taskComments.put(trelloCommentTaskId, updatedTaskComments);
                        } else {
                            List<Object> newTaskComments = new List<Object>();
                            newTaskComments.add(retrievedComment);
                            taskComments.put(trelloCommentTaskId, newTaskComments);
                        }
                    }
                }
            }
        }

        //loop through boards
        for (String boardId : boards.keySet()){
            //see if board matches an account
            String boardName = boards.get(boardId);
            if (accounts.containsKey(boardName)){
                String accountId = accounts.get(boardName);
                //loop through all board's tasks
                for (Object rawTask : trelloTasks.get(boardId)){
                    Map<String, Object> taskFromTrello = (Map<String, Object>) rawTask;
                    String taskId = String.valueOf(taskFromTrello.get('id'));
                    //check if task already exists
                    Boolean taskExists = false;
                    Map<String, Task> accountTasks;
                    if(existingTasks.containsKey(accountId)){
                        accountTasks = existingTasks.get(accountId);
                        if(accountTasks.containsKey(taskId)){
                            taskExists = true;
                        }
                    }

                    if (taskExists) {
                        //if tasks already exists -
                    	//process its updates and put it on the update queue
                    	Task updatedTask = accountTasks.get(taskId);
                        //check for appropriate sObject field-level access on Task
                        if (!Schema.sObjectType.Task.fields.Subject.isUpdateable() || !Schema.sObjectType.Task.fields.Subject.isCreateable()){ throw new myException('cant access Task'); }
                        if (!Schema.sObjectType.Task.fields.Description.isUpdateable() || !Schema.sObjectType.Task.fields.Description.isCreateable()){ throw new myException('cant access Task'); }
                        if (!Schema.sObjectType.Task.fields.ActivityDate.isUpdateable() || !Schema.sObjectType.Task.fields.ActivityDate.isCreateable()){ throw new myException('cant access Task'); }
                        if (!Schema.sObjectType.Task.fields.Trello_Card_ID__c.isUpdateable() || !Schema.sObjectType.Task.fields.Trello_Card_ID__c.isCreateable()){ throw new myException('cant access Task'); }
                        if (!Schema.sObjectType.Task.fields.Status.isUpdateable() || !Schema.sObjectType.Task.fields.Status.isCreateable()){ throw new myException('cant access Task'); }
                        updatedTask = getTask(taskId, updatedTask, taskFromTrello, taskComments);
                    	//put it on the update queue
                    	updatedTasks.add(updatedTask);
	                    //remove it from existingTasks
	                    accountTasks.remove(taskId);
                        existingTasks.put(accountId, accountTasks);
                    } else {
                    	//if task is new -
                    	//process task
                    	Task newTask = getTask(taskId, null, taskFromTrello, taskComments);
                        if (!Schema.sObjectType.Task.fields.WhatId.isUpdateable() || !Schema.sObjectType.Task.fields.WhatId.isCreateable()){ throw new myException('cant access Task'); }
                        if (!Schema.sObjectType.Task.fields.RecordTypeId.isUpdateable() || !Schema.sObjectType.Task.fields.RecordTypeId.isCreateable()){ throw new myException('cant access Task'); }
                        newTask.WhatId = accountId;
                        newTask.RecordTypeId = trelloTaskRecordTypeId;
                    	//add it to the insert queue
                    	newTasks.add(newTask);
                    }

                }
            }
        }
        //delete all tasks remaining on existing Tasks
        //---(since we found no matches in Trello - meaning they must've been deleted, or moved to a new board....)
        for (String accountId : existingTasks.keySet()) {
            Map<String, Task> accountTasksToDelete = existingTasks.get(accountId);
            for (String taskId : accountTasksToDelete.keySet()) {
                if (!Schema.sObjectType.Task.isDeletable()) {
                    throw new myException('cant delete tasks');
                } else {
                 	toDeleteTasks.add(accountTasksToDelete.get(taskId));
                }
            }
        }

        //run DML updates, now that all API calls are done
        if (Schema.sObjectType.Task.isDeletable()
            && Schema.sObjectType.Task.isUpdateable()
            && Schema.sObjectType.Task.isCreateable()) {
			insert newTasks;
        	update updatedTasks;
        	delete toDeleteTasks;
        } else {
            throw new myException('insufficient access to task object');
        }

    }
    webService static void btnRefreshTrello(){
        refreshTrello();
    }
}
