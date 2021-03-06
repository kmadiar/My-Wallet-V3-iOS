//
//  SimpleBuyIneligibleCurrencyViewController.swift
//  Blockchain
//
//  Created by Alex McGregor on 4/2/20.
//  Copyright © 2020 Blockchain Luxembourg S.A. All rights reserved.
//

import PlatformUIKit
import RxSwift

final class SimpleBuyIneligibleCurrencyViewController: UIViewController {
    
    // MARK: - Private IBOutlets
    
    @IBOutlet private var imageView: UIImageView!
    @IBOutlet private var titleLabel: UILabel!
    @IBOutlet private var descriptionLabel: UILabel!
    @IBOutlet private var changeCurrencyButtonView: ButtonView!
    @IBOutlet private var viewHomeButtonView: ButtonView!
    
    // MARK: - Private Properties
    
    private let presenter: SimpleBuyIneligibleCurrencyScreenPresenter
    private let disposeBag = DisposeBag()
    
    // MARK: - Setup
    
    init(presenter: SimpleBuyIneligibleCurrencyScreenPresenter) {
        self.presenter = presenter
        super.init(nibName: SimpleBuyIneligibleCurrencyViewController.objectName, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        titleLabel.content = presenter.titleLabelContent
        descriptionLabel.content = presenter.descriptionLabelContent
        changeCurrencyButtonView.viewModel = presenter.changeCurrencyButtonViewModel
        viewHomeButtonView.viewModel = presenter.viewHomeButtonViewModel
        
        imageView.image = presenter.thumbnail
        
        presenter.dismissalRelay
            .observeOn(MainScheduler.instance)
            .bind(weak: self) { (self) in
                self.dismiss(animated: true, completion: nil)
            }
            .disposed(by: disposeBag)
        
        presenter.restartRelay
            .observeOn(MainScheduler.instance)
            .bind(weak: self) { (self) in
                self.dismiss(animated: true) {
                    self.presenter.resumeSimpleBuy()
                }
            }
            .disposed(by: disposeBag)
    }
    
}
