//
//  PatreonViewController.swift
//  AltStore
//
//  Created by Riley Testut on 9/5/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit
import SafariServices

private enum KittyStoreSupportLinks
{
    static let support = URL(string: "https://buymeacoffee.com/zyn3")!
    static let social = URL(string: "https://x.com/xboxsignout999_?s=21&t=k6RkcjRI6uMwGvJ_q6XC7A")!
    static let repository = URL(string: "https://github.com/NightVibes33/litter")!
}

final class PatreonViewController: UICollectionViewController, UICollectionViewDelegateFlowLayout
{
    private var prototypeAboutHeader: AboutPatreonHeaderView!
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        let aboutHeaderNib = UINib(nibName: "AboutPatreonHeaderView", bundle: Bundle(for: AppDelegate.self))
        self.prototypeAboutHeader = aboutHeaderNib.instantiate(withOwner: nil, options: nil)[0] as? AboutPatreonHeaderView
        
        self.collectionView.register(aboutHeaderNib, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: "AboutHeader")
        self.collectionView.reloadData()
    }
    
    override func viewWillAppear(_ animated: Bool)
    {
        super.viewWillAppear(animated)
        self.collectionView.reloadData()
    }
    
    override func viewDidLayoutSubviews()
    {
        super.viewDidLayoutSubviews()
        
        let layout = self.collectionViewLayout as! UICollectionViewFlowLayout
        
        var itemWidth = (self.collectionView.bounds.width - (layout.sectionInset.left + layout.sectionInset.right + layout.minimumInteritemSpacing)) / 2
        itemWidth.round(.down)
        
        // TODO: if the intention here is to hide the cells, we should just modify the data source. @JoeMatt
        layout.itemSize = CGSize(width: 0, height: 0)
    }

    func prepare(_ headerView: AboutPatreonHeaderView)
    {
        headerView.layoutMargins = self.view.layoutMargins
        headerView.supportButton.addTarget(self, action: #selector(PatreonViewController.openPatreonURL(_:)), for: .primaryActionTriggered)
        headerView.twitterButton.addTarget(self, action: #selector(PatreonViewController.openTwitterURL(_:)), for: .primaryActionTriggered)
        headerView.instagramButton.addTarget(self, action: #selector(PatreonViewController.openInstagramURL(_:)), for: .primaryActionTriggered)
    }
    
    override func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView
    {
        let headerView = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: "AboutHeader", for: indexPath) as! AboutPatreonHeaderView
        self.prepare(headerView)
        return headerView
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, referenceSizeForHeaderInSection section: Int) -> CGSize
    {
        let widthConstraint = self.prototypeAboutHeader.widthAnchor.constraint(equalToConstant: collectionView.bounds.width)
        NSLayoutConstraint.activate([widthConstraint])
        defer { NSLayoutConstraint.deactivate([widthConstraint]) }
        
        self.prepare(self.prototypeAboutHeader)
        return self.prototypeAboutHeader.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
    }

    @objc func openPatreonURL(_ sender: UIButton)
    {
        let safariViewController = SFSafariViewController(url: KittyStoreSupportLinks.support)
        safariViewController.preferredControlTintColor = self.view.tintColor
        self.present(safariViewController, animated: true, completion: nil)
    }
    
    @objc func openTwitterURL(_ sender: UIButton)
    {
        let safariViewController = SFSafariViewController(url: KittyStoreSupportLinks.social)
        safariViewController.preferredControlTintColor = self.view.tintColor
        self.present(safariViewController, animated: true, completion: nil)
    }
    
    @objc func openInstagramURL(_ sender: UIButton)
    {
        let safariViewController = SFSafariViewController(url: KittyStoreSupportLinks.repository)
        safariViewController.preferredControlTintColor = self.view.tintColor
        self.present(safariViewController, animated: true, completion: nil)
    }
}

final class AboutPatreonHeaderView: UICollectionReusableView
{
    @IBOutlet var supportButton: UIButton!
    @IBOutlet var twitterButton: UIButton!
    @IBOutlet var instagramButton: UIButton!
    @IBOutlet var textView: UITextView!
    
    @IBOutlet private var teamIcon: UIImageView!
    @IBOutlet private var teamLabel: UILabel!
    
    override func awakeFromNib()
    {
        super.awakeFromNib()
        
        self.textView.clipsToBounds = true
        self.textView.layer.cornerRadius = 20
        self.textView.textContainer.lineFragmentPadding = 0
        
        self.teamIcon.image = Self.appIconImage() ?? self.teamIcon.image
        for imageView in [self.teamIcon].compactMap({$0})
        {
            imageView.clipsToBounds = true
            imageView.layer.cornerRadius = imageView.bounds.midY
        }
        
        for button in [self.supportButton, self.twitterButton, self.instagramButton].compactMap({$0})
        {
            button.clipsToBounds = true
            button.layer.cornerRadius = 16
        }
    }
    

    private static func appIconImage() -> UIImage?
    {
        let primaryIcon = (Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any])?["CFBundlePrimaryIcon"] as? [String: Any]
        let iconFiles = primaryIcon?["CFBundleIconFiles"] as? [String]
        let names = Array((iconFiles ?? []).reversed()) + ["AppIcon60x60", "AppIcon", "Icon-1024", "brand_logo"]

        for name in names
        {
            if let image = UIImage(named: name) { return image }
            if let url = Bundle.main.url(forResource: name, withExtension: "png"),
               let image = UIImage(contentsOfFile: url.path) { return image }
        }

        return nil
    }

    override func layoutMarginsDidChange()
    {
        super.layoutMarginsDidChange()
        self.textView.textContainerInset = UIEdgeInsets(top: self.layoutMargins.left, left: self.layoutMargins.left, bottom: self.layoutMargins.right, right: self.layoutMargins.right)
    }
}

