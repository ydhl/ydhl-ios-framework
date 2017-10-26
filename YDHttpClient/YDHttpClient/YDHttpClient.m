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
    NSMutableDictionary *headers;
}
@end

@implementation YDHttpClient
- (id)init{
    self = [super init];
    mFetchType = FetchTypeApi;
    mCacheType = CacheTypeIgnore;
    mApiFormat  = ApiFromatJSON;
    headers = [[NSMutableDictionary alloc] init];
    
    if(self){
        mIsDBOpened = [self initDb];
    }
    return self;
}
- (void)clearAllCache{
    if ( ! mIsDBOpened) return;
    
    NSString *sql = @"";
    
    sql = @"delete from CACHES where 1=1";
    sqlite3_stmt *stmt;
    int result = sqlite3_prepare_v2(mDatabase, [sql UTF8String], -1, &stmt, nil) ;
    if (result != SQLITE_OK) {
        return;
    }
    
    int rst = sqlite3_step(stmt);
    if (rst != SQLITE_DONE)
        NSLog(@"delete ALL CACHE Something is Wrong(%d)!", rst);
    
    sqlite3_finalize(stmt);
    
    return;

}
-(void)clearCookie{
    [self removeCache:@"Set-Cookie"];
}
- (void)setHeader:(NSString *)header forName:(NSString *)name{
    [headers setObject:header forKey:name];
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


-(void)saveCache:(NSString *)data For:(NSInteger )what delegate:(id<YDHttpClientDelegate>)deletage{
    [self saveCacheForKey:[deletage getCacheKeyFor:what] withData:data];
}

-(NSString *)fetchCacheFor:(NSString *)key{
    
    NSDictionary *cache = [self getCacheByKey:key];
    
    if ([self cacheIsEmpty:cache]) {
        return nil;
    }
    return [cache objectForKey:@"value"];
}
-(NSString *)fetchCacheFor:(NSInteger )what delegate:(id<YDHttpClientDelegate>)deletage{
    mDelegate = deletage;
    
    NSDictionary *cache = [self getCacheByKey:[mDelegate getCacheKeyFor:what]];

    if ([self cacheIsEmpty:cache]) {
        return nil;
    }
    return [cache objectForKey:@"value"];
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
    
    @try {
        if ([self isGet:method] && (mFetchType==FetchTypeCache || mFetchType==FetchTypeCacheElseApi || mFetchType==FetchTypeCacheThenApi || mFetchType==FetchTypeCacheAwaysApi)) {
            
            NSString *key = [mDelegate getCacheKeyFor:mWhat];
            NSDictionary *cache = [self getCacheByKey:key];
            
            //这两种情况直接返回，不调用api
            if (mFetchType==FetchTypeCache || (! [self cacheIsEmpty:cache] && mFetchType==FetchTypeCacheElseApi)){
                NSLog(@"found cache for type: %d key: %@, ignore api invoke", mFetchType, key);
                [mDelegate handleResult:[cache objectForKey:@"value"] for:mWhat hasDone:YES];
                return;
            }
            
            if(mFetchType == FetchTypeCacheThenApi || (! [self cacheIsEmpty:cache] && mFetchType==FetchTypeCacheAwaysApi)){
                NSLog(@"found cache for type: %d key: %@, will invoke api", mFetchType, key);
                [mDelegate handleResult:[cache objectForKey:@"value"] for:mWhat hasDone:mFetchType == FetchTypeCacheAwaysApi];
            }
        }
        
        
        NSLog(@"%@ invoke api: %@ with data:%@", method, uri, data);
        [self call:uri by:method withData:data completionHandler:^(NSURLResponse * res, NSData * resData, NSError * error) {
            NSString *result = nil;
            NSHTTPURLResponse *HTTPResponse = (NSHTTPURLResponse *)res;
            
            
            if ( ! error && resData.length>0 ) {//[HTTPResponse statusCode]==200 500也会返回内容的情况，这个时候不能看着网络错误；只要无错误并有数据返回就看着正常
                result = [[NSString alloc] initWithData:resData encoding:NSUTF8StringEncoding];
                NSDictionary *fields = [HTTPResponse allHeaderFields];
                NSString *cookie = [fields valueForKey:@"Set-Cookie"];
                if(cookie != nil)
                    [self saveCacheForKey:@"Set-Cookie" withData:cookie];
                
                NSLog(@"invoke api success");
                
                if ([self isGet:method] && [mDelegate isCallSuccess:result]) {
                     NSLog(@"is valid data for get invoke, handle cache now");
                    [self handleCacheForResult:result];
                }
            }else{//网络错误
                NSLog(@"%@ \r\n arg:\r\n%@ response:\r\n%@ \r\nerror:\r\n%@ \r\nresult:\r\n%@", HTTPResponse, data, [[NSString alloc] initWithData:resData encoding:NSUTF8StringEncoding], [error description], result);
                if([self isGet:method] && mFetchType == FetchTypeApiElseCache){
                    NSDictionary *cache = [self getCacheByKey:[mDelegate getCacheKeyFor:mWhat]];
                    if(! [self cacheIsEmpty:cache]){
                        result = [cache objectForKey:@"value"];
                    }
                }
            }
            
            if ([self isGet:method] && mFetchType==FetchTypeCacheAwaysApi) {
                NSDictionary *cache = [self getCacheByKey:[mDelegate getCacheKeyFor:mWhat]];
                if (! [self cacheIsEmpty:cache]) {
                    return;
                }
            }
            
            //非get请求时，网络错误的情况下，也把请求的数据交给handleCache处理
            if (error && ! [self isGet:method]) {
                [self handleCacheForResult:data];
            }
            
            if (error==nil && result==nil){//两者都未nil，表示无网络错误，但api没有正确返回内容，如出现了500；
                result = @"";
            }
            
            dispatch_async(dispatch_get_main_queue(), ^{
                if(error ){//error不为nil，表示有网络错误；
                    [mDelegate onNetworkError:mWhat error:error ? [error description] : @"Server Error"];
                }
                if(result != nil){//result表示有数据返回，但这时候可能也有网络错误（onNetworkError会被调用），这时进handleResult是因为缓存策略
                    [mDelegate handleResult:result for:mWhat hasDone:YES];
                }
            });
            
            return;
            
        }];
    } @catch (NSException *exception) {
        NSLog(@"NSException: %@", exception);
    } @finally {
        
    }
}

#pragma mark - 网络请求私有方法

-(void)handleCacheForResult:(id)result{
    NSString *key = [mDelegate getCacheKeyFor:mWhat];
    if (key==nil) {
        return;
    }
    switch (mCacheType) {
        case CacheTypeCustom:{
            
            NSDictionary *cache = [self getCacheByKey:key];
            if ( ! [self cacheIsEmpty:cache]) {
                [self saveCacheForKey:key withData:[mDelegate handleCache:result ToCache:[cache objectForKey:@"value"] For:mWhat]];
            }else{
                [self saveCacheForKey:key withData:[mDelegate handleCache:result ToCache:nil For:mWhat] ];
            }
            break;
        }
        case CacheTypeReplace:
            [self saveCacheForKey:key withData:! [result isKindOfClass:[NSString class]] ? [YDHttpClient stringFromJSON:result] : result];
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

    
    [self setHeaders:request];
        
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
//        [body appendFormat:@"Content-Disposition: form-data; name=\"%@\"\r\n\r\n",[self urlencodeForString:key]];
        [body appendFormat:@"Content-Disposition: form-data; name=\"%@\"\r\n\r\n",key];
        id v = [postParems objectForKey:key];
//        [body appendFormat:@"%@\r\n", [v isKindOfClass:[NSString class]] ? [self urlencodeForString:v] : v];
        [body appendFormat:@"%@\r\n", v];
        
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
    [request setValue:[NSString stringWithFormat:@"%d", [myRequestData length]] forHTTPHeaderField:@"Content-Length"];
    [request setHTTPBody:myRequestData];
    [request setHTTPMethod:@"POST"];
    
    NSLog(@"%@", [[NSString alloc] initWithData:myRequestData encoding:NSUTF8StringEncoding]);
    
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
    [self setHeaders:request];
    
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
-(void)removeCache:(NSString *)key{
    if ( ! mIsDBOpened) return;
    
    NSString *sql = @"";
    
    sql = @"delete from CACHES where name=?";
    sqlite3_stmt *stmt;
    int result = sqlite3_prepare_v2(mDatabase, [sql UTF8String], -1, &stmt, nil) ;
    if (result != SQLITE_OK) {
        return;
    }
    
    
    sqlite3_bind_text(stmt, 1, [key UTF8String], -1, NULL);
    int rst = sqlite3_step(stmt);
    if (rst != SQLITE_DONE)
        NSLog(@"delete CACHE Something is Wrong(%d)!", rst);
    
    sqlite3_finalize(stmt);
    
    return;

}
-(void)saveCacheForKey:(NSString *)key withData:(NSString *)data{
    if ( ! mIsDBOpened) return;
    
    if (data == nil) {
        [self removeCache:key];
        return;
    }
    
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
-(BOOL)isGet:(NSString *)method{
    return [@"get" caseInsensitiveCompare:method]==NSOrderedSame;
}

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


- (void)setHeaders:(NSMutableURLRequest *)request {
    NSDictionary *cookie = [self getCacheByKey:@"Set-Cookie"];
    if( ! [self cacheIsEmpty:cookie]){
        NSString *cookieStr = [cookie objectForKey:@"value"];
        NSRange  range = [cookieStr rangeOfString:@";"];
        [request addValue:@"keep-alive" forHTTPHeaderField:@"Connection"];
        [request addValue:[cookieStr substringToIndex: range.location] forHTTPHeaderField:@"Cookie"];
    }
    [request addValue:@"yes" forHTTPHeaderField:@"X-YDHTTP-CLIENT"];
    for (NSString *header in [headers allKeys]) {
        [request addValue:[headers objectForKey:header] forHTTPHeaderField:header];
    }
}
@end
