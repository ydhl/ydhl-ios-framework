//
//  YDHttpClient.m
//  YDHttpClient
//
//  Created by leeboo on 14-9-1.
//  Copyright (c) 2014年 ydhl. All rights reserved.
//

#import "YDHttpClient.h"

@interface YDHttpClient(){
    FetchType mFetchType;
    CacheType mCacheType;
    sqlite3 *mDatabase;
    BOOL mIsDBOpened;
    id<YDHttpClientDelegate> mDelegate;
    NSInteger mWhat;
    ApiFromat mApiFormat;
    NSArray *mFiles;
}
@end

@implementation YDHttpClient
- (id)init{
    self = [super init];
    mFetchType = FetchTypeApi;
    mCacheType = CacheTypeIgnore;
    mApiFormat  = ApiFromatJSON;
    if(self){
        mIsDBOpened = [self initDb];
    }
    return self;
}

- (id)initByFetch:(FetchType)fetchType andCache:(CacheType) cacheType {
    self = [super init];
    mFetchType = fetchType;
    mCacheType = cacheType;
    mApiFormat  = ApiFromatJSON;
    if(self){
        mIsDBOpened = [self initDb];
    }
    return self;
}

-(void)changeFetch:(FetchType)fetchType andCache:(CacheType) cacheType{
    mFetchType = fetchType;
    mCacheType = cacheType;
}

-(void)callApiByPost:(NSString *)uri for:(NSInteger)w withData:(NSDictionary *)data withFile:(NSArray *)files delegate:(id<YDHttpClientDelegate>)deletage{
    mFiles = files;
    [self callApi:uri for:w by:@"post" withData:data delegate:deletage];
}

-(void)callApi:(NSString *)uri for:(NSInteger )w  by:(NSString *)method withData:(NSDictionary *)data delegate:(id<YDHttpClientDelegate>) dge{
    mDelegate = dge;
    mWhat =w;
    
    if (mFetchType==FetchTypeCache || mFetchType==FetchTypeCacheElseApi || mFetchType==FetchTypeCacheThenApi || mFetchType==FetchTypeCacheAwaysApi) {
        
        NSDictionary *cache = [self getCacheByKey:[mDelegate getCacheKeyFor:mWhat]];
        
        //这两种情况直接返回，不调用api
        if (mFetchType==FetchTypeCache || (! [self cacheIsEmpty:cache] && mFetchType==FetchTypeCacheElseApi)){
            [mDelegate handleResult:[cache objectForKey:@"value"] for:mWhat hasDone:YES];
            return;
        }
        
        if(mFetchType == FetchTypeCacheThenApi || (! [self cacheIsEmpty:cache] && mFetchType==FetchTypeCacheAwaysApi)){
            [mDelegate handleResult:[cache objectForKey:@"value"] for:mWhat hasDone:mFetchType == FetchTypeCacheAwaysApi];
        }
    }
    
    

    [self call:uri by:method withData:data completionHandler:^(NSURLResponse * res, NSData * resData, NSError * error) {
        NSString *result = nil;
        if ( ! error) {
            result = [[NSString alloc] initWithData:resData encoding:NSUTF8StringEncoding];
            if ([mDelegate isCallSuccess:result]) {
                [self handleCacheForResult:result];
            }
        }else{//网络错误
            NSLog(@"%@", [error description]);
            if(mFetchType == FetchTypeApiElseCache){
                NSDictionary *cache = [self getCacheByKey:[mDelegate getCacheKeyFor:mWhat]];
                if(! [self cacheIsEmpty:cache]){
                    result = [cache objectForKey:@"value"];
                }
            }
        }
        
        if (mFetchType==FetchTypeCacheAwaysApi) {
            NSDictionary *cache = [self getCacheByKey:[mDelegate getCacheKeyFor:mWhat]];
            if (! [self cacheIsEmpty:cache]) {
                return;
            }
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if(error){
                [mDelegate onNetworkError:mWhat error:[error description]];
            }else{
                [mDelegate handleResult:result for:mWhat hasDone:YES];
            }
        });
        
        return;
        
    }];

}

#pragma mark - 网络请求私有方法

-(void)handleCacheForResult:(NSString *)result{
    NSString *key = [mDelegate getCacheKeyFor:mWhat];
    if (key==nil) {
        return;
    }
    switch (mCacheType) {
        case CacheTypeAppend:{
            
            NSDictionary *cache = [self getCacheByKey:key];
            if ( ! [self cacheIsEmpty:cache]) {
                [self saveCacheForKey:key withData:[mDelegate appendResultFrom:result To:[cache objectForKey:@"value"]]];
            }else{
                [self saveCacheForKey:key withData:result];
            }
            break;
        }
        case CacheTypePrepend:
        {
            NSDictionary *cache = [self getCacheByKey:key];
            if (! [self cacheIsEmpty:cache]) {
                [self saveCacheForKey:key withData:[mDelegate prependResultFrom:result To:[cache objectForKey:@"value"]]];
            }else{
                [self saveCacheForKey:key withData:result];
            }
            break;
        }
        case CacheTypeReplace:
            [self saveCacheForKey:key withData:result];
            break;
        case CacheTypeIgnore:
        default:
            break;
    }
}

-(NSString *)urlencodeForString:(NSString *)string{
    return CFBridgingRelease(CFURLCreateStringByAddingPercentEscapes(kCFAllocatorDefault,
                                                                                   (CFStringRef)string,
                                                                                   NULL,
                                                                                   (CFStringRef)@"!*'();:@&=+$,/?%#[]",
                                                                                   kCFStringEncodingUTF8));
}
-(NSString *)urlencode:(NSDictionary *)data{
    NSString *httpData = @"";
    
    
    if (data!=nil) {
        for (NSString * key in data.keyEnumerator) {
            id value =  [data objectForKey:key];
            
            if ([value isKindOfClass:[NSString class]]) {//url转义
                value = [self urlencodeForString:value];
            }else if(value==nil || [value isEqual:[NSNull null]]){
                value = @"";
            }
            httpData = [httpData stringByAppendingFormat:@"%@=%@&", key, value];
        }
    }
    return httpData;
}

- (void)postFileCall:(NSString *)uri withData:(NSDictionary *)postParems  completionHandler:(void (^)(NSURLResponse*, NSData*, NSError*)) handler{
    
    NSString *TWITTERFON_FORM_BOUNDARY = @"GZYDHLYDHttpClient2010";
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:uri]];
    NSString *MPboundary=[[NSString alloc]initWithFormat:@"--%@",TWITTERFON_FORM_BOUNDARY];
    NSString *endMPboundary=[[NSString alloc]initWithFormat:@"%@--",MPboundary];
    
    NSMutableString *body=[[NSMutableString alloc]init];
    
    NSArray *keys= [postParems allKeys];
    
    for(NSString *key in keys)
    {
        if ([mFiles indexOfObject:key] != NSNotFound) {//file handle later
            continue;
        }
        
        [body appendFormat:@"%@\r\n",MPboundary];
        [body appendFormat:@"Content-Disposition: form-data; name=\"%@\"\r\n\r\n",[self urlencodeForString:key]];
        [body appendFormat:@"%@\r\n", [self urlencodeForString:[postParems objectForKey:key]]];
        
    }
    
    
    NSMutableData *myRequestData=[NSMutableData data];
    [myRequestData appendData:[body dataUsingEncoding:NSUTF8StringEncoding]];
    
    for (NSString *fileName in mFiles) {
        NSData* data;
        NSString * filepath = [postParems objectForKey:fileName];
        
        data = [NSData dataWithContentsOfFile:filepath];
        
        NSMutableString *fileBody=[[NSMutableString alloc]init];
        
        [fileBody appendFormat:@"%@\r\n",MPboundary];
        
        [fileBody appendFormat:@"Content-Disposition: form-data; name=\"%@\"; filename=\"%@\"\r\n",fileName,filepath];

        [fileBody appendFormat:@"Content-Type: application/octet-stream\r\n\r\n"];

        [myRequestData appendData:[fileBody dataUsingEncoding:NSUTF8StringEncoding]];
        
        [myRequestData appendData:data];
    }
    
    NSString *end=[[NSString alloc]initWithFormat:@"\r\n%@",endMPboundary];
    
    [myRequestData appendData:[end dataUsingEncoding:NSUTF8StringEncoding]];
    
    NSString *content=[[NSString alloc]initWithFormat:@"multipart/form-data; boundary=%@",TWITTERFON_FORM_BOUNDARY];
    [request setValue:content forHTTPHeaderField:@"Content-Type"];
    [request setValue:[NSString stringWithFormat:@"%ld", [myRequestData length]] forHTTPHeaderField:@"Content-Length"];
    [request setHTTPBody:myRequestData];
    [request setHTTPMethod:@"POST"];
    
    
    
    NSOperationQueue *queue = [[NSOperationQueue alloc] init];
    [queue setName:@"YDHttpClientPostFile"];
    
    [NSURLConnection sendAsynchronousRequest:request queue:queue completionHandler:handler];
    
}

- (void)call:(NSString *)uri by: (NSString *)httpMethod withData:(NSDictionary *)httpData  completionHandler:(void (^)(NSURLResponse*, NSData*, NSError*)) handler{
    NSString *data = [self urlencode:httpData];
    
    if ([mFiles count]>0) {
        [self postFileCall:uri withData:httpData  completionHandler: handler];
        return;
    }
    
    httpMethod = [httpMethod uppercaseString];
    NSURL *url = nil;
    if ([httpMethod isEqualToString:@"GET"]) {
        url = [NSURL URLWithString: [NSString stringWithFormat:@"%@?%@", uri, data]];
    }else{
        url = [NSURL URLWithString:uri];
    }
    if(url==nil){
        NSLog(@"build url error %@, %@", uri, data);
    }
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    
    
    if([httpMethod isEqualToString:@"POST"]){
        NSString *msgLength = [NSString stringWithFormat:@"%ld", (unsigned long)[data length]];
        [request addValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
        [request addValue:msgLength forHTTPHeaderField:@"Content-Length"];
        [request setHTTPBody:[data dataUsingEncoding:NSUTF8StringEncoding allowLossyConversion:NO]];
    }
    [request setHTTPMethod: httpMethod];
    
    NSOperationQueue *queue = [[NSOperationQueue alloc] init];
    [queue setName:@"YDHttpClient"];
    
    [NSURLConnection sendAsynchronousRequest:request queue:queue completionHandler:handler];
}

#pragma mark - 缓存处理
-(BOOL)initDb{
    NSArray  *documentPaths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDir = [documentPaths objectAtIndex:0];
    NSString *databasePath = [documentsDir stringByAppendingPathComponent:@"ydhlcache"];
    int result = sqlite3_open([databasePath UTF8String], &mDatabase);
    if (result != SQLITE_OK) {
        sqlite3_close(mDatabase);
        return NO;
    }
    
    
    char *errorMsg;
    const char *createSQL = "CREATE TABLE IF NOT EXISTS CACHES (id INTEGER PRIMARY KEY AUTOINCREMENT, name VARCHAR(45), value TEXT, modified_on DATETIME)";
    result = sqlite3_exec(mDatabase, createSQL, NULL, NULL, &errorMsg);
    if(result != SQLITE_OK){
        sqlite3_close(mDatabase);
        return NO;
    }
    return YES;
}
-(BOOL)cacheIsEmpty:(NSDictionary *)cache{
    if(cache==nil)return YES;
    if([[cache objectForKey:@"id"] intValue]==0)return YES;
    return NO;
}
-(void)saveCacheForKey:(NSString *)key withData:(NSString *)data{
    if ( ! mIsDBOpened) return;
    NSDictionary *cache = [self getCacheByKey:key];
    
    NSString *sql = @"";
    
    if ([self cacheIsEmpty:cache]) {
        sql = @"insert into CACHES(name, value, modified_on) VALUES(?,?,?)";
        sqlite3_stmt *stmt;
        int result = sqlite3_prepare_v2(mDatabase, [sql UTF8String], -1, &stmt, nil) ;
        if (result != SQLITE_OK) {
            return;
        }
        
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        [formatter setDateFormat:@"yyyy-m-d H:i:s"];
        
        sqlite3_bind_text(stmt, 1, [key UTF8String], -1, NULL);
        sqlite3_bind_text(stmt, 2, [data UTF8String], -1, NULL);
        sqlite3_bind_text(stmt, 3, [[formatter stringFromDate:[[NSDate alloc] init]] UTF8String], -1, NULL);
        int rst = sqlite3_step(stmt);
        if (rst != SQLITE_DONE)
            NSLog(@"INSERT CACHE Something is Wrong(%d)!", rst);
        
        sqlite3_finalize(stmt);
        
        return;
    }
    
    sql = @"update CACHES set value=?, modified_on=? where id=?";
    sqlite3_stmt *stmt;
    if (sqlite3_prepare_v2(mDatabase, [sql UTF8String], -1, &stmt, nil) != SQLITE_OK) {
        return;
    }
    
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"yyyy-mm-dd H:i:s"];
    
    sqlite3_bind_text(stmt, 1, [data UTF8String], -1, NULL);
    sqlite3_bind_text(stmt, 2, [[formatter stringFromDate:[[NSDate alloc] init]] UTF8String], -1, NULL);
    sqlite3_bind_int(stmt, 3, [[cache objectForKey:@"id"] intValue]);
    
    int result = sqlite3_step(stmt);
    if (result != SQLITE_DONE)
        NSLog(@"UPDATE CACHE Something is Wrong(%d)!", result);
    
    sqlite3_finalize(stmt);
    
    return;
    
}
-(NSDictionary *)getCacheByKey:(NSString *)key{
    if ( ! mIsDBOpened) return nil;
    
    const char * sql = "SELECT id,name,value,modified_on from CACHES where name=?";
    sqlite3_stmt *stmt;
    if (sqlite3_prepare_v2(mDatabase, sql, -1, &stmt, nil) != SQLITE_OK) {
        return nil;
    }
    
    sqlite3_bind_text(stmt, 1, [key UTF8String], -1, NULL);
    
    NSMutableDictionary *result = [[NSMutableDictionary alloc] initWithObjectsAndKeys:@"",@"id",@"",@"name",@"",@"value",@"",@"mofified", nil];
    
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        NSString *rowId     = [[NSString alloc] initWithUTF8String: (char *)sqlite3_column_text(stmt, 0)];
        NSString *rowName   = [[NSString alloc] initWithUTF8String:(char *)sqlite3_column_text(stmt, 1)];
        NSString *rowValue  = [[NSString alloc] initWithUTF8String:(char *)sqlite3_column_text(stmt, 2)];
        NSString *rowDate   = [[NSString alloc] initWithUTF8String:(char *)sqlite3_column_text(stmt, 3)];
        [result setValue:rowId      forKey:@"id"];
        [result setValue:rowName    forKey:@"name"];
        [result setValue:rowValue   forKey:@"value"];
        [result setValue:rowDate    forKey:@"mofified"];
    }
    
    sqlite3_finalize(stmt);
    return result;
    
}

#pragma mark - 助手方法
/**
 * @brief json 格式字符串解析成json格式
 */
+(NSJSONSerialization *)getJson:(NSString *)data{
    if (data==nil || [data isEqual:[NSNull null]]) {
        return nil;
    }
    NSError *error = nil;
    NSJSONSerialization *json = [NSJSONSerialization JSONObjectWithData:[data dataUsingEncoding:NSUTF8StringEncoding] options:NSJSONReadingMutableContainers error:&error];
    if (error) {
        return nil;
    }
    return json;
}
/**
 * @brief 解析成json格式字符串
 */
+(NSString *)stringFromJSON:(NSJSONSerialization *)data{
    if (data==nil || [data isEqual:[NSNull null]]) {
        return nil;
    }
    NSError *error = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:data options:NSJSONWritingPrettyPrinted  error:&error];
    
    if ([jsonData length] > 0 && error == nil){
        return [[NSString alloc] initWithData:jsonData  encoding:NSUTF8StringEncoding];
    }else{
        return nil;
    }
}
@end
