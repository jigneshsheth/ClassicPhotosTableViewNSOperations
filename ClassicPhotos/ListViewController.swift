//
//  ListViewController.swift
//  ClassicPhotos
//
//  Created by Richard Turton on 03/07/2014.
//  Copyright (c) 2014 raywenderlich. All rights reserved.
//

import UIKit
import CoreImage

let dataSourceURL = NSURL(string:"http://www.raywenderlich.com/downloads/ClassicPhotosDictionary.plist")

class ListViewController: UITableViewController {
  
  var photos = [PhotoRecord]()
  let pendingOperations = PendingOperations()
  
  
  override func viewDidLoad() {
    super.viewDidLoad()
    self.title = "Classic Photos"
    self.fetchPhotoDetails()
  }
  
  override func didReceiveMemoryWarning() {
    super.didReceiveMemoryWarning()
  }
  
  // #pragma mark - Table view data source
  override func tableView(tableView: UITableView?, numberOfRowsInSection section: Int) -> Int {
    return photos.count
  }
  
//  override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
//    let cell = tableView.dequeueReusableCellWithIdentifier("CellIdentifier", forIndexPath: indexPath) 
//    let rowKey = photos.allKeys[indexPath.row] as! String
//    
//    var image : UIImage?
//    if let imageURL = NSURL(string:photos[rowKey] as! String),
//    imageData = NSData(contentsOfURL:imageURL){
//      //1
//      let unfilteredImage = UIImage(data:imageData)
//      //2
//      image = self.applySepiaFilter(unfilteredImage!)
//    }
//    
//    // Configure the cell...
//    cell.textLabel?.text = rowKey
//    if image != nil {
//      cell.imageView?.image = image!
//    }
//    
//    return cell
//  }
  
  
  override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
    let cell = tableView.dequeueReusableCellWithIdentifier("CellIdentifier", forIndexPath: indexPath) 
    
    //1
    if cell.accessoryView == nil {
      let indicator = UIActivityIndicatorView(activityIndicatorStyle: .Gray)
      cell.accessoryView = indicator
    }
    let indicator = cell.accessoryView as! UIActivityIndicatorView
    
    //2
    let photoDetails = photos[indexPath.row]
    
    //3
    cell.textLabel?.text = photoDetails.name
    cell.imageView?.image = photoDetails.image
    
    //4
    switch (photoDetails.state){
    case .Filtered:
      indicator.stopAnimating()
    case .Failed:
      indicator.stopAnimating()
      cell.textLabel?.text = "Failed to load"
    case .New, .Downloaded:
      indicator.startAnimating()
      if (!tableView.dragging && !tableView.decelerating) {
        self.startOperationsForPhotoRecord(photoDetails, indexPath: indexPath)
      }
    }
    
    return cell
  }
  
  override func scrollViewWillBeginDragging(scrollView: UIScrollView) {
    //1
    suspendAllOperations()
  }
  
  override func scrollViewDidEndDragging(scrollView: UIScrollView, willDecelerate decelerate: Bool) {
    // 2
    if !decelerate {
      loadImagesForOnscreenCells()
      resumeAllOperations()
    }
  }
  
  override func scrollViewDidEndDecelerating(scrollView: UIScrollView) {
    // 3
    loadImagesForOnscreenCells()
    resumeAllOperations()
  }
  
  
  func suspendAllOperations () {
    pendingOperations.downloadQueue.suspended = true
    pendingOperations.filtrationQueue.suspended = true
  }
  
  func resumeAllOperations () {
    pendingOperations.downloadQueue.suspended = false
    pendingOperations.filtrationQueue.suspended = false
  }
  
  func loadImagesForOnscreenCells () {
    //1
    
    if let pathsArray = tableView.indexPathsForVisibleRows {
      //2
      var allPendingOperations = Set(pendingOperations.downloadsInProgress.keys)
      allPendingOperations.unionInPlace(pendingOperations.filtrationsInProgress.keys)
      
      //3
      var toBeCancelled = allPendingOperations
      let visiblePaths = Set(pathsArray )
      toBeCancelled.subtractInPlace(visiblePaths)
      
      //4
      var toBeStarted = visiblePaths
      toBeStarted.subtractInPlace(allPendingOperations)
      
      // 5
      for indexPath in toBeCancelled {
        if let pendingDownload = pendingOperations.downloadsInProgress[indexPath] {
          pendingDownload.cancel()
        }
        pendingOperations.downloadsInProgress.removeValueForKey(indexPath)
        if let pendingFiltration = pendingOperations.filtrationsInProgress[indexPath] {
          pendingFiltration.cancel()
        }
        pendingOperations.filtrationsInProgress.removeValueForKey(indexPath)
      }
      
      // 6
      for indexPath in toBeStarted {
        let indexPath = indexPath as NSIndexPath
        let recordToProcess = self.photos[indexPath.row]
        startOperationsForPhotoRecord(recordToProcess, indexPath: indexPath)
      }
    }
  }
  func applySepiaFilter(image:UIImage) -> UIImage? {
    let inputImage = CIImage(data:UIImagePNGRepresentation(image)!)
    let context = CIContext(options:nil)
    let filter = CIFilter(name:"CISepiaTone")
    filter!.setValue(inputImage, forKey: kCIInputImageKey)
    filter!.setValue(0.8, forKey: "inputIntensity")
    if let outputImage = filter!.outputImage {
      let outImage = context.createCGImage(outputImage, fromRect: outputImage.extent)
      return UIImage(CGImage: outImage)
    }
    return nil
    
  }
  
  
  func startOperationsForPhotoRecord(photoDetails: PhotoRecord, indexPath: NSIndexPath){
    switch (photoDetails.state) {
    case .New:
      startDownloadForRecord(photoDetails, indexPath: indexPath)
    case .Downloaded:
      startFiltrationForRecord(photoDetails, indexPath: indexPath)
    default:
      print("do nothing")
    }
  }
  
  func startDownloadForRecord(photoDetails: PhotoRecord, indexPath: NSIndexPath){
    //1
    if let _ = pendingOperations.downloadsInProgress[indexPath] {
      return
    }
    
    //2
    let downloader = ImageDownloader(photoRecord: photoDetails)
    //3
    downloader.completionBlock = {
      if downloader.cancelled {
        return
      }
      dispatch_async(dispatch_get_main_queue(), {
        self.pendingOperations.downloadsInProgress.removeValueForKey(indexPath)
        self.tableView.reloadRowsAtIndexPaths([indexPath], withRowAnimation: .Fade)
      })
    }
    //4
    pendingOperations.downloadsInProgress[indexPath] = downloader
    //5
    pendingOperations.downloadQueue.addOperation(downloader)
  }
  
  func startFiltrationForRecord(photoDetails: PhotoRecord, indexPath: NSIndexPath){
    if let _ = pendingOperations.filtrationsInProgress[indexPath]{
      return
    }
    
    let filterer = ImageFiltration(photoRecord: photoDetails)
    filterer.completionBlock = {
      if filterer.cancelled {
        return
      }
      dispatch_async(dispatch_get_main_queue(), {
        self.pendingOperations.filtrationsInProgress.removeValueForKey(indexPath)
        self.tableView.reloadRowsAtIndexPaths([indexPath], withRowAnimation: .Fade)
      })
    }
    pendingOperations.filtrationsInProgress[indexPath] = filterer
    pendingOperations.filtrationQueue.addOperation(filterer)
  }
  
  func fetchPhotoDetails() {
    let request = NSURLRequest(URL:dataSourceURL!)
    UIApplication.sharedApplication().networkActivityIndicatorVisible = true
    
    NSURLConnection.sendAsynchronousRequest(request, queue: NSOperationQueue.mainQueue()) {response,data,error in
      if data != nil {
        let datasourceDictionary = try! NSPropertyListSerialization.propertyListWithData(data!, options:[], format: nil) as! NSDictionary
        
        for(key,value) in datasourceDictionary {
          let name = key as? String
          let url = NSURL(string:value as? String ?? "")
          if name != nil && url != nil {
            let photoRecord = PhotoRecord(name:name!, url:url!)
            self.photos.append(photoRecord)
          }
        }
        
        self.tableView.reloadData()
      }
      
      if error != nil {
        let alert = UIAlertView(title:"Oops!",message:error!.localizedDescription, delegate:nil, cancelButtonTitle:"OK")
        alert.show()
      }
      UIApplication.sharedApplication().networkActivityIndicatorVisible = false
    }
  }
  
  
  
  
}
