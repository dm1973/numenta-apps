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

import Foundation
import MessageUI

/** class for handling social aspects of app
*/
class ShareService  {
    
    var mailDelegate : MFMailComposeViewControllerDelegate?
    /** provides a UI to share a screen shot of the current view
        - parameter controller: controller to take a screen shot of
    */
    func share( controller: UIViewController){
        let screenshot = takeScreenshot (controller)
        let objectsToShare = [screenshot]
        let activityVC = UIActivityViewController(activityItems: objectsToShare, applicationActivities: nil)
        
        controller.presentViewController(activityVC, animated: true, completion: nil)
    }
    
    
    /** provides a UI to send an email with a screen shot of the current view
    - parameter controller: controller to take a screen shot of
    */
    func feedback (controller: UIViewController, presenter: MFMailComposeViewControllerDelegate){
        
        mailDelegate = presenter
        // make sure mail is configured.
        if (MFMailComposeViewController.canSendMail() == false){
            
            
            let alert = UIAlertController(title: "Unable to send mail", message:
                "Your device could not send e-mail.  Please check e-mail configuration and try again.", preferredStyle: UIAlertControllerStyle.Alert)
            alert.addAction(UIAlertAction(title: "Ok", style: UIAlertActionStyle.Default, handler: nil))
            controller.presentViewController(alert, animated: true, completion: nil)
            return
        }

        let mailController = MFMailComposeViewController()
        mailController.mailComposeDelegate = presenter
        
        mailController.setToRecipients(["support@numenta.com"])
        mailController.setSubject("feedback")
       // mailController.setMessageBody( Log.log, isHTML: false)
        //Log.log = ""
        
        // create attachment and convert to a jpeg
        let screenshot = takeScreenshot (controller)
        let myData = UIImageJPEGRepresentation(screenshot, 0.9);
        mailController.addAttachmentData(myData!, mimeType:"image/jpg" ,fileName:"screenshot.jpg")
        
        controller.presentViewController(mailController, animated: true, completion: nil)
    }
    
    /** creates a screenshot of the view of the passed in controller
    */
    func takeScreenshot(controller :UIViewController)->UIImage{
        let view = controller.view
        UIGraphicsBeginImageContext(view.frame.size)
        view.layer.renderInContext(UIGraphicsGetCurrentContext()!)
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return image
    }
    
   
    
}